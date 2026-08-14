//! The global shortcut.
//!
//! On macOS this goes through Carbon's `RegisterEventHotKey`, which — unlike
//! key *monitoring* — needs no Accessibility permission. So the hotkey itself
//! works on first launch; only reading the selection is gated. That is why a
//! refused permission still leaves a usable app rather than an inert one.

use tauri::App;
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

use crate::popup;

/// Cmd+Shift+D on macOS, Ctrl+Shift+D elsewhere.
///
/// D for "define". Shift is in the combination because the two-modifier space
/// is far less contested than single-modifier chords — Cmd+D alone is Bookmark
/// in every browser.
pub fn default_shortcut() -> Shortcut {
    #[cfg(target_os = "macos")]
    let modifiers = Modifiers::SUPER | Modifiers::SHIFT;
    #[cfg(not(target_os = "macos"))]
    let modifiers = Modifiers::CONTROL | Modifiers::SHIFT;

    Shortcut::new(Some(modifiers), Code::KeyD)
}

pub fn init(app: &App) -> tauri::Result<()> {
    let shortcut = default_shortcut();

    app.handle().plugin(
        tauri_plugin_global_shortcut::Builder::new()
            .with_handler(move |app, _shortcut, event| {
                // Fire on press only. Without this the popup is summoned twice
                // per keypress — once down, once up.
                if event.state() == ShortcutState::Pressed {
                    popup::toggle_with_selection(app);
                }
            })
            .build(),
    )?;

    // A failure here is almost always another app already owning the
    // combination. Log and carry on: the tray and `--show` still work, so the
    // app is reachable. Refusing to start over a taken hotkey would be worse
    // than starting without one.
    if let Err(e) = app.global_shortcut().register(shortcut) {
        eprintln!(
            "ktranslate: could not register the global shortcut ({e}). \
             Use the tray icon, or `ktranslate-app --show`, until it is changed in settings."
        );
    }

    Ok(())
}
