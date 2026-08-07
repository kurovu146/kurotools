//! Summoning the popup.
//!
//! The ordering in [`show_with_selection`] is the subtle part and is easy to
//! get backwards.

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, WebviewWindow};

pub const MAIN_WINDOW: &str = "main";

/// Event the frontend listens for. Carries either captured text or the reason
/// there wasn't any.
pub const CAPTURE_EVENT: &str = "tra://capture";

#[derive(Clone, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum CaptureEvent {
    /// Text was captured; the frontend should look it up.
    Text { text: String },
    /// Nothing was selected. Not an error state — a hint.
    Empty,
    /// Capture is impossible until macOS Accessibility is granted.
    NeedsPermission,
}

pub fn main_window(app: &AppHandle) -> Option<WebviewWindow> {
    app.get_webview_window(MAIN_WINDOW)
}

/// Capture the selection, then show the popup with it.
///
/// **Capture must happen before the window is shown.** Showing our window
/// first takes keyboard focus away from whatever the user was reading, so the
/// synthesized Cmd+C would then be delivered to *us* instead of to the app
/// holding the selection — and the capture would come back empty every time.
/// The window only appears once there is something to put in it.
pub fn show_with_selection(app: &AppHandle) {
    let app = app.clone();

    // Capture polls the clipboard for up to COPY_TIMEOUT. On the UI thread that
    // is a visible freeze of whatever the user is doing.
    tauri::async_runtime::spawn_blocking(move || {
        let event = capture_now();
        show(&app);
        let _ = app.emit(CAPTURE_EVENT, event);
    });
}

fn capture_now() -> CaptureEvent {
    use tra_core::capture::{self, CaptureError};

    if !capture::has_accessibility_permission() {
        return CaptureEvent::NeedsPermission;
    }

    match capture::capture_selection() {
        Ok(text) if !text.trim().is_empty() => CaptureEvent::Text { text },
        Ok(_) | Err(CaptureError::NothingSelected) => {
            // Fall back to whatever is on the clipboard. The user may have
            // copied manually — the documented degraded path when Accessibility
            // is refused, and the only path at all on GNOME/Wayland.
            match capture::read_clipboard() {
                Ok(text) if !text.trim().is_empty() => CaptureEvent::Text { text },
                _ => CaptureEvent::Empty,
            }
        }
        Err(_) => CaptureEvent::Empty,
    }
}

/// Let the popup appear over another app's **fullscreen** Space.
///
/// `set_visible_on_all_workspaces` sets `CanJoinAllSpaces`, which covers
/// ordinary desktop Spaces and nothing else. A fullscreen app owns its own
/// Space, and macOS will not put a window there unless the window also
/// declares `FullScreenAuxiliary` — so with only `CanJoinAllSpaces` the popup
/// reports visible, focused and correctly positioned while being impossible to
/// see. Tauri exposes no API for this, hence reaching for the `NSWindow`.
///
/// Both flags are set together deliberately: `setCollectionBehavior` replaces
/// the whole mask rather than adding to it, so setting only the new flag would
/// undo the call above.
///
/// # Call this once, at startup, from the main thread
///
/// Two reasons it cannot live in [`show`]:
///
/// - AppKit is main-thread-only and `show` runs on a blocking worker, so it
///   would need `run_on_main_thread` — which is **asynchronous**. The closure
///   would be queued and `window.show()` would run first, placing the window
///   before the behaviour applied. Calling it from `setup` needs no dispatch
///   at all, because `setup` already runs on the main thread.
/// - Tauri's `set_visible_on_all_workspaces` is itself a
///   `setCollectionBehavior` call carrying only `CanJoinAllSpaces`, so the two
///   overwrite each other. This function sets both flags, which makes that
///   call redundant — `show` no longer makes it.
///
/// Calling `setCollectionBehavior` off the main thread crashed the app with
/// `EXC_BREAKPOINT` inside `-[NSWindow setCollectionBehavior:]`. Tauri's own
/// window methods hide that by dispatching internally; a raw objc2 call does
/// not, which is the invariant `MainThreadMarker` enforces and that casting a
/// raw pointer bypasses.
#[cfg(target_os = "macos")]
pub fn configure_space_behavior(window: &WebviewWindow) {
    use objc2_app_kit::{NSWindow, NSWindowCollectionBehavior};

    let ptr = match window.ns_window() {
        Ok(p) => p,
        Err(e) => {
            eprintln!("tra: no NSWindow handle: {e}");
            return;
        }
    };
    if ptr.is_null() {
        return;
    }

    // SAFETY: Tauri hands back the live NSWindow backing this webview window;
    // the reference is used only for the duration of this call, and the caller
    // guarantees the main thread, as AppKit requires.
    unsafe {
        let ns_window = &*(ptr as *const NSWindow);
        let wanted = NSWindowCollectionBehavior::CanJoinAllSpaces
            | NSWindowCollectionBehavior::FullScreenAuxiliary;
        // CanJoinAllSpaces covers ordinary desktop Spaces. FullScreenAuxiliary
        // is what allows the window into another app's fullscreen Space — the
        // case that matters for a fullscreen terminal. Set together because
        // setCollectionBehavior replaces the mask rather than adding to it.
        ns_window.setCollectionBehavior(wanted);
    }
}

/// Non-macOS: Tauri's own API is enough, and there is no fullscreen-Space
/// concept to work around.
#[cfg(not(target_os = "macos"))]
pub fn configure_space_behavior(window: &WebviewWindow) {
    if let Err(e) = window.set_visible_on_all_workspaces(true) {
        eprintln!("tra: could not make the window follow workspaces: {e}");
    }
}

/// Gap between the pointer and the popup's corner, in physical pixels.
/// Enough that the window does not open underneath the cursor.
const CURSOR_GAP: i32 = 12;

/// Show, focus, and position the popup near the cursor.
pub fn show(app: &AppHandle) {
    let Some(window) = main_window(app) else {
        // Silent failure here presents as "the hotkey does nothing", with no
        // error anywhere, so it is worth a line on stderr.
        eprintln!(
            "tra: no window labelled {MAIN_WINDOW:?}; labels present: {:?}",
            app.webview_windows().keys().collect::<Vec<_>>()
        );
        return;
    };

    // Nothing here touches the window's Space behaviour: that is set once at
    // startup by configure_space_behavior. Setting it per-show meant an async
    // main-thread hop that landed after window.show(), and Tauri's
    // set_visible_on_all_workspaces overwriting the fullscreen flag each time.

    // Best-effort: failing to position is not a reason to withhold the window.
    // It would simply open wherever it last was.
    if let Err(e) = position_at_cursor(app, &window) {
        eprintln!("tra: could not position the window: {e}");
    }
    if let Err(e) = window.show() {
        eprintln!("tra: could not show the window: {e}");
    }
    if let Err(e) = window.set_focus() {
        eprintln!("tra: could not focus the window: {e}");
    }
}

/// Put the popup beside the pointer, fully inside the monitor the pointer is on.
///
/// Centring on the *primary* monitor is what the first version did, and on a
/// multi-monitor desk that means the popup reliably opens on a screen the user
/// is not looking at — it appears not to work at all. The pointer is the best
/// available proxy for "where the user is", since the text they just selected
/// is under it.
fn position_at_cursor(app: &AppHandle, window: &WebviewWindow) -> tauri::Result<()> {
    let cursor = app.cursor_position()?;

    // The monitor under the pointer, not the window's current one — the window
    // has not moved yet, so its own monitor is still the previous location's.
    let monitor = match app.monitor_from_point(cursor.x, cursor.y)? {
        Some(m) => m,
        None => match app.primary_monitor()? {
            Some(m) => m,
            None => return Ok(()),
        },
    };

    let area = monitor.size();
    let origin = monitor.position();
    let size = window.outer_size()?;

    // Clamp so the whole window stays on that monitor. Without this, selecting
    // text near the right or bottom edge opens the popup half off-screen —
    // and `max(origin)` after `min` also covers a monitor smaller than the
    // window, where the two bounds cross.
    let max_x = origin.x + area.width as i32 - size.width as i32;
    let max_y = origin.y + area.height as i32 - size.height as i32;
    let x = (cursor.x as i32 + CURSOR_GAP).min(max_x).max(origin.x);
    let y = (cursor.y as i32 + CURSOR_GAP).min(max_y).max(origin.y);

    window.set_position(tauri::PhysicalPosition::new(x, y))
}

/// Hide the popup. Never closes it — recreating a webview on every lookup
/// would put a visible delay in front of the one interaction that must feel
/// instant.
pub fn hide(app: &AppHandle) {
    if let Some(window) = main_window(app) {
        let _ = window.hide();
    }
}
