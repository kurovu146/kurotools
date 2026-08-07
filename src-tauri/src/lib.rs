//! The Tauri shell.
//!
//! Deliberately thin: window, tray, hotkey, IPC. Everything worth testing
//! lives in `tra-core`, which knows nothing about Tauri.

mod commands;
mod hotkey;
mod popup;
mod state;
mod tray;

use tauri::Manager;

/// Passing this to an already-running instance summons the popup.
///
/// The documented escape hatch for Wayland compositors where the global
/// shortcut never fires: the user binds `tra --show` in their own compositor
/// config and gets the same behaviour the built-in hotkey would have given.
const SHOW_FLAG: &str = "--show";

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // Must be registered before anything else so a second launch is
        // intercepted rather than half-initialising a duplicate app.
        .plugin(tauri_plugin_single_instance::init(|app, argv, _cwd| {
            if argv.iter().any(|a| a == SHOW_FLAG) {
                popup::show_with_selection(app);
            } else {
                popup::show(app);
            }
        }))
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_positioner::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec![SHOW_FLAG]),
        ))
        .invoke_handler(tauri::generate_handler![
            commands::lookup,
            commands::hide_popup,
            commands::save_word,
            commands::unsave_word,
            commands::is_saved,
            commands::saved_words,
            commands::recent_lookups,
            commands::speak,
            commands::tts_available,
            commands::check_accessibility,
            commands::request_accessibility,
            commands::open_accessibility_settings,
        ])
        .setup(|app| {
            // A database that will not open must not stop the app starting.
            // Lookups are the product; history and saved words are extras, and
            // losing them is far better than refusing to launch. The commands
            // that need state use try_state and degrade when it is absent.
            match state::AppState::new(app.handle()) {
                Ok(s) => {
                    app.manage(s);
                }
                Err(e) => eprintln!("tra: storage unavailable, continuing without it ({e})"),
            }

            // A menu-bar utility, not an app you switch to: no Dock icon, and
            // showing the popup must not deactivate the app the user is
            // reading. Accessory is what buys both.
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            tray::init(app)?;
            hotkey::init(app)?;

            // Hidden until summoned. The window exists from launch so the
            // first hotkey press has no webview startup cost in front of it.
            if let Some(window) = app.get_webview_window(popup::MAIN_WINDOW) {
                let _ = window.hide();
            }

            Ok(())
        })
        .on_window_event(|window, event| {
            // Clicking away dismisses, like any other popover. Hide rather
            // than close: closing the last window would exit the app on some
            // platforms, and rebuilding the webview would put a delay in front
            // of the next lookup.
            if let tauri::WindowEvent::Focused(false) = event {
                let _ = window.hide();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
