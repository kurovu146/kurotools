//! Manual spike for selection capture. Run it, select text somewhere, wait.
//!
//!     cargo run -p tra-core --example capture_spike
//!
//! This is the riskiest slice of the whole product isolated from everything
//! else: no UI, no translation, no storage, no hotkey. It answers three
//! questions that the rest of the design assumes the answer to:
//!
//!   1. Can we read the selection from an arbitrary application at all?
//!   2. Does the user's clipboard survive the round trip?
//!   3. How long does it actually take?
//!
//! If any answer is bad, the "select, then hotkey" model needs rethinking
//! before a UI is built on top of it.

use std::io::Write;
use std::time::{Duration, Instant};

const COUNTDOWN: u64 = 5;
/// Sentinel placed on the clipboard before capture. If capture restores
/// correctly this exact string is back afterwards; anything else means the
/// user's real clipboard would have been destroyed.
const CANARY: &str = "tra-spike-canary-do-not-lose-me";

fn main() {
    println!("tra — selection capture spike\n");

    #[cfg(target_os = "macos")]
    {
        if tra_core::capture::has_accessibility_permission() {
            println!("Accessibility: granted");
        } else {
            println!("Accessibility: NOT granted — asking now.");
            println!("Grant it in System Settings, then re-run.\n");
            tra_core::capture::request_accessibility_permission();
            // Without the permission, CGEvent::post silently does nothing, so
            // continuing would only produce a confusing "nothing was selected".
            return;
        }
    }

    // Seed the clipboard so restoration is verifiable rather than assumed.
    match set_clipboard(CANARY) {
        Ok(()) => println!("Clipboard seeded with a canary value."),
        Err(e) => {
            println!("Could not seed the clipboard: {e}");
            return;
        }
    }

    println!("\nSelect some text in ANY application now.");
    #[cfg(target_os = "linux")]
    println!("(Linux reads the PRIMARY selection — selecting is enough, don't copy.)");
    #[cfg(not(target_os = "linux"))]
    println!("(Just select it — do NOT press Cmd/Ctrl+C. That is what we're testing.)");

    for remaining in (1..=COUNTDOWN).rev() {
        print!("\r  capturing in {remaining}... ");
        let _ = std::io::stdout().flush();
        std::thread::sleep(Duration::from_secs(1));
    }
    println!("\r  capturing now...        \n");

    let started = Instant::now();
    let result = tra_core::capture::capture_selection();
    let elapsed = started.elapsed();

    match result {
        Ok(text) => {
            println!("CAPTURED in {:?}", elapsed);
            println!("  chars: {}", text.chars().count());
            println!("  bytes: {}", text.len());
            println!("  text : {:?}", truncate(&text, 300));
        }
        Err(e) => {
            println!("FAILED after {:?}: {e}", elapsed);
        }
    }

    // Question 2, and the one most likely to be quietly wrong.
    //
    // Checked twice, deliberately. An immediate check passes even when the
    // application's copy is still in flight and about to overwrite what we
    // restored — which is exactly the bug this found in Ghostty/tmux, where
    // the write landed after the restore. The second check, one second later,
    // is the one that actually tells the truth.
    println!();
    report_clipboard("immediately");
    std::thread::sleep(Duration::from_secs(1));
    report_clipboard("one second later");
}

fn report_clipboard(when: &str) {
    match get_clipboard() {
        Ok(after) if after == CANARY => println!("Clipboard intact {when}."),
        Ok(after) => {
            println!("CLIPBOARD LOST {when} — this is a bug.");
            println!("  expected: {CANARY:?}");
            println!("  found   : {:?}", truncate(&after, 120));
        }
        Err(e) => println!("Could not read the clipboard back {when}: {e}"),
    }
}

fn truncate(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        return s.to_owned();
    }
    s.chars().take(max).collect::<String>() + "…"
}

fn set_clipboard(text: &str) -> Result<(), String> {
    arboard::Clipboard::new()
        .map_err(|e| e.to_string())?
        .set_text(text.to_owned())
        .map_err(|e| e.to_string())
}

fn get_clipboard() -> Result<String, String> {
    arboard::Clipboard::new()
        .map_err(|e| e.to_string())?
        .get_text()
        .map_err(|e| e.to_string())
}
