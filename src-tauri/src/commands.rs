//! The IPC surface. Thin by design — every command here should be a couple of
//! lines that hand off to `tra-core`, so the logic stays testable without a
//! GUI and the shell stays swappable.

use tauri::{AppHandle, Manager, State};
use tra_core::capture;
use tra_core::model::Lookup;
use tra_core::provider::GtxProvider;
use tra_core::store::{HistoryEntry, SavedWord};
use tra_core::tts;

use crate::popup;
use crate::state::AppState;

/// Look `text` up and return the three-pane result.
///
/// Runs on the blocking pool: the provider makes two synchronous HTTP requests
/// and holding the async runtime's thread for a round trip would freeze the
/// popup that is already on screen.
///
/// Infallible by contract — `GtxProvider::lookup` turns every failure into an
/// "unavailable" result, so the frontend never needs a rejection path.
#[tauri::command]
pub async fn lookup(app: AppHandle, text: String) -> Lookup {
    let result = tauri::async_runtime::spawn_blocking(move || GtxProvider::new().lookup(&text))
        .await
        // The only way to land here is a panic inside the provider. Returning
        // the same "unavailable" shape keeps the frontend's single code path
        // intact rather than surfacing a second kind of failure.
        .unwrap_or_else(|_| Lookup::unavailable(String::new(), false));

    // History is a convenience, not part of the answer. A failing write must
    // never cost the user the lookup they are waiting on.
    if let Some(state) = app.try_state::<AppState>() {
        if let Ok(store) = state.store.lock() {
            let _ = store.record_lookup(&result);
        }
    }

    result
}

/// Dismiss the popup. Called on Esc.
#[tauri::command]
pub fn hide_popup(app: AppHandle) {
    popup::hide(&app);
}

// -- storage ----------------------------------------------------------------

#[tauri::command]
pub fn save_word(state: State<'_, AppState>, word: String) -> Result<(), String> {
    let store = state.store.lock().map_err(|e| e.to_string())?;
    store.save_word(&word).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn unsave_word(state: State<'_, AppState>, word: String) -> Result<(), String> {
    let store = state.store.lock().map_err(|e| e.to_string())?;
    store.unsave_word(&word).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn is_saved(state: State<'_, AppState>, word: String) -> Result<bool, String> {
    let store = state.store.lock().map_err(|e| e.to_string())?;
    store.is_saved(&word).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn saved_words(state: State<'_, AppState>) -> Result<Vec<SavedWord>, String> {
    let store = state.store.lock().map_err(|e| e.to_string())?;
    store.saved_words().map_err(|e| e.to_string())
}

#[tauri::command]
pub fn recent_lookups(
    state: State<'_, AppState>,
    limit: usize,
) -> Result<Vec<HistoryEntry>, String> {
    let store = state.store.lock().map_err(|e| e.to_string())?;
    store.recent(limit).map_err(|e| e.to_string())
}

// -- pronunciation ----------------------------------------------------------

#[tauri::command]
pub fn speak(text: String) -> Result<(), String> {
    tts::speak(&text).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn tts_available() -> bool {
    tts::is_available()
}

// -- permissions ------------------------------------------------------------

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
