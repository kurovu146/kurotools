//! The Tauri shell.
//!
//! Deliberately thin: window, tray, hotkey, IPC. Everything worth testing
//! lives in `tra-core`, which knows nothing about Tauri.

mod commands;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![commands::lookup])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
