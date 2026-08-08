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
/// Hotkey entry point: show the popup, or dismiss it if it is already up.
///
/// Pressing the hotkey while the popup is up dismisses it. Esc and click-away
/// also work, but the toggle is the reliable one: the popup is shown without
/// activating the application, so focus behaviour around it is subtler than for
/// an ordinary window.
pub fn toggle_with_selection(app: &AppHandle) {
    if let Some(window) = main_window(app) {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
            return;
        }
    }
    show_with_selection(app);
}

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

/// Turn the popup into a non-activating `NSPanel`.
///
/// This is the only arrangement that satisfies both requirements at once, and
/// it took ruling out every alternative to establish:
///
/// - Activating the app (Tauri's `set_focus`, or `NSApp.activate`) *does* place
///   the window over a fullscreen app — by forcing macOS off that Space, which
///   yanks the user away from what they were reading.
/// - Not activating keeps the Space, but a plain `NSWindow` then cannot be
///   placed on it at all, and receives no keyboard input.
///
/// A panel with `NSWindowStyleMaskNonactivatingPanel` resolves the
/// contradiction: it can be shown and take key events **without** its
/// application becoming active, so the fullscreen Space stays put and Esc still
/// works.
///
/// Called once from `setup`, which already runs on the main thread.
#[cfg(target_os = "macos")]
pub fn configure_space_behavior(app: &AppHandle) {
    use tauri_nspanel::cocoa::appkit::NSWindowCollectionBehavior;
    use tauri_nspanel::WebviewWindowExt as _;

    let Some(window) = main_window(app) else {
        return;
    };

    let panel = match window.to_panel() {
        Ok(panel) => panel,
        Err(e) => {
            eprintln!("tra: could not convert the window to an NSPanel: {e:?}");
            return;
        }
    };

    // 1 << 7 — NSWindowStyleMaskNonactivatingPanel. The whole reason for the
    // panel: showing it does not activate the application.
    const NONACTIVATING_PANEL: i32 = 1 << 7;
    panel.set_style_mask(NONACTIVATING_PANEL);

    // Permit the panel onto any Space, including another app's fullscreen one.
    panel.set_collection_behaviour(
        NSWindowCollectionBehavior::NSWindowCollectionBehaviorCanJoinAllSpaces
            | NSWindowCollectionBehavior::NSWindowCollectionBehaviorFullScreenAuxiliary,
    );

    // Float above ordinary windows. NSFloatingWindowLevel.
    panel.set_level(3);

    // Without this the panel vanishes whenever another app becomes active,
    // which for a popup summoned over someone else's window is immediate.
    panel.set_hides_on_deactivate(false);

    // Last, because `set_style_mask` above is what breaks the transparency
    // this restores.
    sync_appearance(&window);
}

/// Make the window agree with the system about how it should look: the right
/// light/dark appearance, and transparent so the vibrancy layer is what shows.
///
/// Both halves fix the same symptom — a flat slab where a translucent panel
/// should be — from opposite directions:
///
/// - `NSVisualEffectView` takes its colour from the window's
///   `effectiveAppearance`. Left unset it rendered *light* on a dark desktop,
///   so the CSS switched to dark text while the material behind it did not,
///   and the panel came out white with near-white writing on it.
/// - Assigning a style mask (see [`configure_space_behavior`]) makes AppKit
///   re-derive the window's opacity. It comes back opaque, painting a solid
///   background straight over the vibrancy view. Tauri set both of these from
///   `"transparent": true` at construction; the panel conversion undoes it.
///
/// **Must run on the main thread** — every AppKit call here does.
#[cfg(target_os = "macos")]
// `objc`'s `msg_send!` expands to `#[cfg(not(feature = "cargo-clippy"))]`, a
// feature no crate here declares, so every call site would otherwise raise an
// `unexpected_cfgs` warning about the macro's own internals.
#[allow(unexpected_cfgs)]
pub fn sync_appearance(window: &WebviewWindow) {
    use tauri_nspanel::objc::runtime::Object;
    use tauri_nspanel::objc::{class, msg_send, sel, sel_impl};

    let ns_window = match window.ns_window() {
        Ok(handle) => handle as *mut Object,
        Err(e) => {
            eprintln!("tra: no NSWindow to set the appearance on ({e})");
            return;
        }
    };

    // An unknown theme means "follow the system", and Aqua is what macOS falls
    // back to itself. Both names are ASCII literals with a trailing NUL, so
    // `stringWithUTF8String:` can read them straight out of the binary.
    let name: &[u8] = if matches!(window.theme(), Ok(tauri::Theme::Dark)) {
        b"NSAppearanceNameDarkAqua\0"
    } else {
        b"NSAppearanceNameAqua\0"
    };

    // SAFETY: called only on the main thread (see the doc comment above), and
    // `ns_window` is a live NSWindow for as long as `window` is.
    unsafe {
        let name: *mut Object = msg_send![class!(NSString), stringWithUTF8String: name.as_ptr()];
        let appearance: *mut Object = msg_send![class!(NSAppearance), appearanceNamed: name];
        if !appearance.is_null() {
            let _: () = msg_send![ns_window, setAppearance: appearance];
        }

        let _: () = msg_send![ns_window, setOpaque: false];
        let clear: *mut Object = msg_send![class!(NSColor), clearColor];
        let _: () = msg_send![ns_window, setBackgroundColor: clear];
    }
}

/// Non-macOS: Tauri's own API is enough, and there is no fullscreen-Space
/// concept to work around.
#[cfg(not(target_os = "macos"))]
pub fn configure_space_behavior(app: &AppHandle) {
    if let Some(window) = main_window(app) {
        if let Err(e) = window.set_visible_on_all_workspaces(true) {
            eprintln!("tra: could not make the window follow workspaces: {e}");
        }
    }
}

/// Show the panel without activating the application.
///
/// `make_key_window` on a non-activating panel gives it keyboard focus while
/// leaving the frontmost application active — which is what restores Esc and
/// typing that the plain-`NSWindow` approach had to give up.
///
/// **Must run on the main thread.** `tauri-nspanel` calls straight into AppKit
/// without dispatching, and `show` runs on a blocking worker so capture cannot
/// freeze the UI. Calling it directly from there crashed with `EXC_BREAKPOINT`
/// inside `-[NSWindow _doOrderWindow:]`. Tauri's own window methods dispatch
/// internally and hide this; the plugin's do not.
#[cfg(target_os = "macos")]
fn show_panel(app: &AppHandle) {
    let app = app.clone();
    let dispatched = app.clone().run_on_main_thread(move || {
        use tauri_nspanel::ManagerExt as _;

        // Re-applied on every show rather than once at startup: the user can
        // switch appearance, or cross the auto light/dark boundary at dusk,
        // while this long-lived utility sits in the tray.
        if let Some(window) = main_window(&app) {
            sync_appearance(&window);
        }

        match app.get_webview_panel(MAIN_WINDOW) {
            Ok(panel) => {
                panel.order_front_regardless();
                panel.make_key_window();
            }
            Err(e) => eprintln!("tra: no panel registered for {MAIN_WINDOW:?}: {e:?}"),
        }
    });

    if let Err(e) = dispatched {
        eprintln!("tra: could not reach the main thread to show the panel: {e}");
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

    // Space behaviour is configured once at startup by configure_space_behavior.

    // Best-effort: failing to position is not a reason to withhold the window.
    // It would simply open wherever it last was.
    if let Err(e) = position_at_cursor(app, &window) {
        eprintln!("tra: could not position the window: {e}");
    }
    // macOS goes through the panel, which shows and takes keys without making
    // this application active — see configure_space_behavior.
    #[cfg(target_os = "macos")]
    show_panel(app);

    #[cfg(not(target_os = "macos"))]
    {
        if let Err(e) = window.show() {
            eprintln!("tra: could not show the window: {e}");
        }
        if let Err(e) = window.set_focus() {
            eprintln!("tra: could not focus the window: {e}");
        }
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
    // The panel is ordered out directly. Tauri's window.hide() operates on the
    // NSWindow it thinks it owns, which after the panel conversion is no longer
    // the whole story.
    #[cfg(target_os = "macos")]
    {
        // Same main-thread requirement as show_panel: order_out is an AppKit
        // call and the callers here include the hotkey handler's thread.
        let handle = app.clone();
        let _ = app.clone().run_on_main_thread(move || {
            use tauri_nspanel::ManagerExt as _;
            match handle.get_webview_panel(MAIN_WINDOW) {
                Ok(panel) => panel.order_out(None),
                Err(_) => {
                    if let Some(window) = handle.get_webview_window(MAIN_WINDOW) {
                        let _ = window.hide();
                    }
                }
            }
        });
        return;
    }

    #[cfg(not(target_os = "macos"))]
    if let Some(window) = main_window(app) {
        let _ = window.hide();
    }
}
