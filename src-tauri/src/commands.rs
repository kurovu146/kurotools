//! The IPC surface. Thin by design — every command here should be a couple of
//! lines that hand off to `tra-core`, so the logic stays testable without a
//! GUI and the shell stays swappable.

use tauri::AppHandle;
use tra_core::capture;
use tra_core::model::Lookup;
use tra_core::provider::GtxProvider;

use crate::popup;

/// Look `text` up and return the three-pane result.
///
/// Runs on the blocking pool: the provider makes two synchronous HTTP requests
/// and holding the async runtime's thread for a round trip would freeze the
/// popup that is already on screen.
///
/// Infallible by contract — `GtxProvider::lookup` turns every failure into an
/// "unavailable" result, so the frontend never needs a rejection path.
#[tauri::command]
pub async fn lookup(text: String) -> Lookup {
    tauri::async_runtime::spawn_blocking(move || GtxProvider::new().lookup(&text))
        .await
        // The only way to land here is a panic inside the provider. Returning
        // the same "unavailable" shape keeps the frontend's single code path
        // intact rather than surfacing a second kind of failure.
        .unwrap_or_else(|_| Lookup::unavailable(String::new(), false))
}

/// Dismiss the popup. Called on Esc.
#[tauri::command]
pub fn hide_popup(app: AppHandle) {
    popup::hide(&app);
}

/// Whether the app may synthesize the copy keystroke. Always true off macOS.
///
/// The permission gate polls this rather than checking once, so a grant made
/// in System Settings takes effect without restarting the app.
#[tauri::command]
pub fn check_accessibility() -> bool {
    capture::has_accessibility_permission()
}

/// Raise macOS's own Accessibility prompt.
#[tauri::command]
pub fn request_accessibility() -> bool {
    capture::request_accessibility_permission()
}

/// Open System Settings directly at the Accessibility pane.
///
/// Deep-linking beats describing where to click: the path is four levels down
/// and macOS has renamed it more than once.
#[tauri::command]
pub fn open_accessibility_settings() {
    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("open")
            .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            .spawn();
    }
}
