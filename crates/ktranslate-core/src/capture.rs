//! Reading the text the user currently has selected, in any application.
//!
//! This is the riskiest part of the product, and it is four different
//! mechanisms rather than one:
//!
//! | Platform      | Mechanism                              | Permission    |
//! |---------------|----------------------------------------|---------------|
//! | macOS         | synthesize Cmd+C, read pasteboard      | Accessibility |
//! | Windows       | synthesize Ctrl+C, read clipboard      | none          |
//! | Linux / X11   | read the PRIMARY selection directly    | none          |
//! | Linux/Wayland | read PRIMARY via wlr-data-control      | none*         |
//!
//! \* GNOME does not implement `wlr-data-control`, so PRIMARY reads fail
//! there and the caller must fall back to [`read_clipboard`].
//!
//! # The clipboard must survive
//!
//! On macOS and Windows there is no way to read another application's
//! selection directly, so we synthesize a copy keystroke — which overwrites
//! whatever the user had on their clipboard. Silently destroying that is the
//! single most annoying bug this class of app can have, so every synthesizing
//! path saves the previous contents first and restores them afterwards,
//! **including when the capture fails**. See [`capture_selection`].
//!
//! Linux/X11 needs none of this: selecting text already populates PRIMARY, so
//! there is nothing to synthesize and the clipboard is never touched.

use std::time::Duration;

/// How long to wait after synthesizing the copy keystroke before giving up.
///
/// This is a race we cannot fully win: the target application handles the
/// keystroke asynchronously and there is no completion signal to wait on. The
/// mitigation is [`capture_selection`]'s change-detection loop, which polls
/// rather than sleeping once and hoping — this value is the polling budget,
/// not a fixed sleep, so a fast app still answers in ~20ms.
///
/// Measured on real hardware: a successful capture from a browser takes
/// **~100ms**. This budget is deliberately ~8× that, to absorb a loaded
/// machine or a slow application, and costs nothing when things are quick
/// because the loop exits on the first observed change.
///
/// It is not set higher, because the budget is also what the user waits when
/// there is genuinely nothing to capture — and that case is common (see the
/// tmux note on [`capture_selection`]). The earlier 450ms "slow copies" that
/// suggested a larger budget were a misreading: those were tmux never copying
/// at all, not a copy arriving late.
const COPY_TIMEOUT: Duration = Duration::from_millis(800);

/// After a failed capture, keep watching this long for a late write.
///
/// The dangerous ordering is: poll times out, we restore the clipboard, and
/// only *then* does the application's copy land — silently overwriting what we
/// just put back. Watching a little longer and restoring again closes that
/// window. Only runs on the failure path; a successful capture has already
/// seen the write, so nothing can still be in flight.
const LATE_WRITE_GRACE: Duration = Duration::from_millis(600);

/// Gap between polls while waiting for the clipboard to change.
const POLL_INTERVAL: Duration = Duration::from_millis(20);

#[derive(Debug, thiserror::Error)]
pub enum CaptureError {
    #[error("clipboard unavailable: {0}")]
    Clipboard(String),

    /// The copy keystroke could not be synthesized. On macOS this is almost
    /// always missing Accessibility permission.
    #[error("could not synthesize the copy keystroke: {0}")]
    Synthesize(String),

    /// The keystroke was sent but the clipboard never changed. Usually means
    /// nothing was actually selected.
    #[error("nothing was selected")]
    NothingSelected,
}

type Result<T> = std::result::Result<T, CaptureError>;

/// Read the regular clipboard. Needs no permission on any platform.
///
/// This is the degraded path: when Accessibility is refused on macOS, or on
/// GNOME/Wayland where PRIMARY cannot be read, the user copies manually and
/// we read the result. Slightly worse UX, zero permissions, always works.
pub fn read_clipboard() -> Result<String> {
    let mut cb = arboard::Clipboard::new().map_err(|e| CaptureError::Clipboard(e.to_string()))?;
    cb.get_text()
        .map_err(|e| CaptureError::Clipboard(e.to_string()))
}

/// Capture the text the user currently has selected.
///
/// On Linux this reads PRIMARY and leaves the clipboard completely alone. On
/// macOS and Windows it saves the clipboard, synthesizes a copy, polls until
/// the clipboard changes (or [`COPY_TIMEOUT`] elapses), then restores the
/// saved contents before returning — on every path, success or failure.
///
/// # Terminal multiplexers cannot be captured this way
///
/// Verified in Ghostty with `set -g mouse on`: a drag creates a **tmux**
/// selection, which tmux owns internally and only hands to the system
/// clipboard on an explicit copy binding. The synthesized copy keystroke goes
/// to the terminal emulator, which has no selection of its own, so nothing is
/// ever written and this returns [`CaptureError::NothingSelected`].
///
/// This is a property of how multiplexers work, not a bug here, and it cannot
/// be fixed from this side. Callers should fall back to [`read_clipboard`] so
/// the user's own copy binding still feeds a lookup.
pub fn capture_selection() -> Result<String> {
    #[cfg(target_os = "linux")]
    {
        read_primary_selection()
    }

    #[cfg(not(target_os = "linux"))]
    {
        capture_via_synthesized_copy()
    }
}

/// Linux: selecting text already puts it in PRIMARY, so just read it. No
/// synthesis, no clipboard damage, no permission.
#[cfg(target_os = "linux")]
fn read_primary_selection() -> Result<String> {
    use arboard::{GetExtLinux, LinuxClipboardKind};

    let mut cb = arboard::Clipboard::new().map_err(|e| CaptureError::Clipboard(e.to_string()))?;
    let text = cb
        .get()
        .clipboard(LinuxClipboardKind::Primary)
        .text()
        // GNOME/Wayland lands here: it does not implement wlr-data-control,
        // so PRIMARY is unreadable. Fall back rather than fail — the user may
        // well have copied manually.
        .or_else(|_| {
            cb.get_text()
                .map_err(|e| CaptureError::Clipboard(e.to_string()))
        })?;

    if text.trim().is_empty() {
        return Err(CaptureError::NothingSelected);
    }
    Ok(text)
}

/// macOS and Windows: save clipboard, synthesize copy, poll, restore.
#[cfg(not(target_os = "linux"))]
fn capture_via_synthesized_copy() -> Result<String> {
    let mut cb = arboard::Clipboard::new().map_err(|e| CaptureError::Clipboard(e.to_string()))?;

    // An empty clipboard and an unreadable one (e.g. it holds an image) are
    // both "no text to put back", which restore treats as "clear it".
    let saved = cb.get_text().ok();

    // Deliberately NOT clearing the clipboard first. Clearing would give a
    // clean change signal, but if synthesis then fails we would have
    // destroyed the user's clipboard to learn nothing. Instead we compare
    // against `saved` and accept the one ambiguity that creates: selecting
    // text identical to what is already on the clipboard reads as "no
    // change". That resolves to NothingSelected, and re-pressing the hotkey
    // with the same text still returns the correct string via `saved`.
    let outcome = synthesize_copy().and_then(|()| poll_for_change(&mut cb, saved.as_deref()));

    restore_clipboard(&mut cb, saved.as_deref());

    // Only the failure path can still have a write in flight: a success has
    // already observed the application's write, so nothing is pending. After a
    // timeout the copy may yet land and silently overwrite what was just
    // restored — measured happening for real in Ghostty/tmux.
    if outcome.is_err() {
        guard_against_late_write(&mut cb, saved.as_deref());
    }

    outcome
}

/// Watch for a write that arrives after the restore, and undo it.
///
/// Returns as soon as one is caught, or when [`LATE_WRITE_GRACE`] elapses.
/// Best-effort by nature — an application slower than the grace window still
/// wins — but it converts the common case from "clipboard silently destroyed"
/// into "clipboard preserved".
#[cfg(not(target_os = "linux"))]
fn guard_against_late_write(cb: &mut arboard::Clipboard, saved: Option<&str>) {
    let deadline = std::time::Instant::now() + LATE_WRITE_GRACE;
    let expected = saved.unwrap_or_default();

    while std::time::Instant::now() < deadline {
        std::thread::sleep(POLL_INTERVAL);

        match cb.get_text() {
            Ok(current) if current != expected => {
                restore_clipboard(cb, saved);
                return;
            }
            // An unreadable clipboard here means someone put a non-text value
            // on it, which is itself a write we should undo.
            Err(_) if saved.is_some() => {
                restore_clipboard(cb, saved);
                return;
            }
            _ => {}
        }
    }
}

/// Poll until the clipboard differs from `previous`, or the budget runs out.
///
/// Polling rather than a single fixed sleep: a fast application responds in
/// ~20ms and the user should not wait 400ms for it, while a slow one would
/// miss a fixed 100ms sleep entirely.
#[cfg(not(target_os = "linux"))]
fn poll_for_change(cb: &mut arboard::Clipboard, previous: Option<&str>) -> Result<String> {
    let deadline = std::time::Instant::now() + COPY_TIMEOUT;

    loop {
        if let Ok(current) = cb.get_text() {
            let changed = match previous {
                Some(prev) => current != prev,
                None => !current.is_empty(),
            };
            if changed && !current.trim().is_empty() {
                return Ok(current);
            }
        }

        if std::time::Instant::now() >= deadline {
            return Err(CaptureError::NothingSelected);
        }
        std::thread::sleep(POLL_INTERVAL);
    }
}

/// Put `saved` back. Best-effort by design: this runs on the failure path too,
/// and a restore error must not mask the original error the caller cares about.
#[cfg(not(target_os = "linux"))]
fn restore_clipboard(cb: &mut arboard::Clipboard, saved: Option<&str>) {
    match saved {
        Some(text) => {
            let _ = cb.set_text(text.to_owned());
        }
        // The user had no text on the clipboard before, so leaving our
        // captured text behind would itself be a modification.
        None => {
            let _ = cb.clear();
        }
    }
}

// ---------------------------------------------------------------------------
// Keystroke synthesis
// ---------------------------------------------------------------------------

/// macOS: post Cmd+C to the session event tap.
///
/// Requires Accessibility permission; without it `CGEvent::post` silently does
/// nothing rather than returning an error, which is why the caller detects
/// failure by the clipboard not changing rather than by a return value. Use
/// [`has_accessibility_permission`] to distinguish "not permitted" from
/// "nothing selected" before blaming the user's selection.
#[cfg(target_os = "macos")]
fn synthesize_copy() -> Result<()> {
    use core_graphics::event::{CGEvent, CGEventFlags, CGEventTapLocation};
    use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};

    const KEY_C: u16 = 8;

    let source = CGEventSource::new(CGEventSourceStateID::HIDSystemState)
        .map_err(|_| CaptureError::Synthesize("could not create a CGEventSource".into()))?;

    let key_down = CGEvent::new_keyboard_event(source.clone(), KEY_C, true)
        .map_err(|_| CaptureError::Synthesize("could not create the key-down event".into()))?;
    key_down.set_flags(CGEventFlags::CGEventFlagCommand);
    key_down.post(CGEventTapLocation::Session);

    let key_up = CGEvent::new_keyboard_event(source, KEY_C, false)
        .map_err(|_| CaptureError::Synthesize("could not create the key-up event".into()))?;
    key_up.set_flags(CGEventFlags::CGEventFlagCommand);
    key_up.post(CGEventTapLocation::Session);

    Ok(())
}

/// Windows: send Ctrl+C via `SendInput`.
#[cfg(target_os = "windows")]
fn synthesize_copy() -> Result<()> {
    use windows::Win32::UI::Input::KeyboardAndMouse::{
        SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_KEYUP,
        VIRTUAL_KEY, VK_C, VK_CONTROL,
    };

    fn key(vk: VIRTUAL_KEY, flags: KEYBD_EVENT_FLAGS) -> INPUT {
        INPUT {
            r#type: INPUT_KEYBOARD,
            Anonymous: INPUT_0 {
                ki: KEYBDINPUT {
                    wVk: vk,
                    wScan: 0,
                    dwFlags: flags,
                    time: 0,
                    dwExtraInfo: 0,
                },
            },
        }
    }

    let inputs = [
        key(VK_CONTROL, KEYBD_EVENT_FLAGS(0)),
        key(VK_C, KEYBD_EVENT_FLAGS(0)),
        key(VK_C, KEYEVENTF_KEYUP),
        key(VK_CONTROL, KEYEVENTF_KEYUP),
    ];

    let sent = unsafe { SendInput(&inputs, std::mem::size_of::<INPUT>() as i32) };
    if sent as usize != inputs.len() {
        return Err(CaptureError::Synthesize(format!(
            "SendInput accepted {sent} of {} events",
            inputs.len()
        )));
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Permissions
// ---------------------------------------------------------------------------

/// Whether this process may synthesize input events (macOS Accessibility).
///
/// Always `true` off macOS, where no such permission exists.
///
/// Note the grant is bound to the app's code signature, so an unsigned rebuild
/// revokes it. Sign development builds with a stable identity to avoid
/// re-granting on every run.
pub fn has_accessibility_permission() -> bool {
    #[cfg(target_os = "macos")]
    {
        unsafe { accessibility_sys::AXIsProcessTrusted() }
    }

    #[cfg(not(target_os = "macos"))]
    {
        true
    }
}

/// Ask macOS to show its "grant Accessibility access" prompt.
///
/// Returns whether permission is *already* held — `false` means the system
/// dialog was raised and the user has not answered yet. The caller should poll
/// [`has_accessibility_permission`] rather than requiring an app restart.
#[cfg(target_os = "macos")]
pub fn request_accessibility_permission() -> bool {
    use core_foundation::base::TCFType;
    use core_foundation::boolean::CFBoolean;
    use core_foundation::dictionary::CFDictionary;
    use core_foundation::string::CFString;

    let key =
        unsafe { CFString::wrap_under_get_rule(accessibility_sys::kAXTrustedCheckOptionPrompt) };
    let options = CFDictionary::from_CFType_pairs(&[(key, CFBoolean::true_value())]);

    unsafe { accessibility_sys::AXIsProcessTrustedWithOptions(options.as_concrete_TypeRef()) }
}

#[cfg(not(target_os = "macos"))]
pub fn request_accessibility_permission() -> bool {
    true
}
