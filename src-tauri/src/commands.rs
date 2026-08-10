//! The IPC surface. Thin by design — every command here should be a couple of
//! lines that hand off to `ktranslate-core`, so the logic stays testable without a
//! GUI and the shell stays swappable.

use ktranslate_core::capture;
use ktranslate_core::config::LangConfig;
use ktranslate_core::lang::{self, Lang};
use ktranslate_core::model::Lookup;
use ktranslate_core::provider::GtxProvider;
use ktranslate_core::store::{HistoryEntry, SavedWord};
use ktranslate_core::tts;
use tauri::{AppHandle, Manager, State};

use crate::popup;
use crate::state::AppState;

/// Look `text` up and return the three-pane result.
///
/// Runs on the blocking pool: the provider makes synchronous HTTP requests and
/// holding the async runtime's thread for a round trip would freeze the popup
/// that is already on screen.
///
/// Infallible by contract — `GtxProvider::lookup` turns every failure into an
/// "unavailable" result, so the frontend never needs a rejection path.
#[tauri::command]
pub async fn lookup(app: AppHandle, text: String) -> Lookup {
    // Read the config before leaving the async context: the store is behind a
    // mutex and the blocking closure must not hold it across a round trip.
    let config = app
        .try_state::<AppState>()
        .and_then(|state| state.store.lock().ok()?.lang_config().ok())
        .unwrap_or_default();

    let result =
        tauri::async_runtime::spawn_blocking(move || GtxProvider::new().lookup(&text, &config))
            .await
            // The only way to land here is a panic inside the provider.
            // Returning the same "unavailable" shape keeps the frontend's
            // single code path intact.
            .unwrap_or_else(|_| Lookup::unavailable(String::new(), false, config.target()));

    // History is a convenience, not part of the answer. A failing write must
    // never cost the user the lookup they are waiting on.
    if let Some(state) = app.try_state::<AppState>() {
        if let Ok(store) = state.store.lock() {
            let _ = store.record_lookup(&result);
        }
    }

    result
}

// -- languages ---------------------------------------------------------------

/// Every language code the endpoint accepts. The frontend turns these into
/// display names itself with `Intl.DisplayNames`.
#[tauri::command]
pub fn languages() -> Vec<&'static str> {
    lang::SUPPORTED.to_vec()
}

#[tauri::command]
pub fn lang_config(state: State<'_, AppState>) -> Result<LangConfig, String> {
    let store = state.store.lock().map_err(|e| e.to_string())?;
    store.lang_config().map_err(|e| e.to_string())
}

/// Store a new language configuration and return what was actually stored.
///
/// The returned value can differ from what was asked for — `LangConfig::new`
/// repairs collisions — so the frontend must render the response rather than
/// its own optimistic guess, or the picker and the app disagree.
#[tauri::command]
pub fn set_lang_config(
    state: State<'_, AppState>,
    source: Option<String>,
    target: String,
    other: String,
) -> Result<LangConfig, String> {
    let parse =
        |code: &str| Lang::from_code(code).ok_or_else(|| format!("unknown language: {code}"));

    // `None` and `"auto"` both mean no source language.
    let source = match source.as_deref() {
        None | Some("auto") => None,
        Some(code) => Some(parse(code)?),
    };
    let config = LangConfig::new(source, parse(&target)?, parse(&other)?);

    let store = state.store.lock().map_err(|e| e.to_string())?;
    store.set_lang_config(&config).map_err(|e| e.to_string())?;
    if let Some(s) = config.source() {
        let _ = store.push_recent_lang(s);
    }
    let _ = store.push_recent_lang(config.target());

    Ok(config)
}

#[tauri::command]
pub fn recent_languages(state: State<'_, AppState>) -> Result<Vec<Lang>, String> {
    let store = state.store.lock().map_err(|e| e.to_string())?;
    store.recent_langs().map_err(|e| e.to_string())
}

/// Dismiss the popup. Called on Esc.
#[tauri::command]
pub fn hide_popup(app: AppHandle) {
    popup::hide(&app);
}

/// Turn dismiss-on-blur off while a screen needs to survive losing focus.
///
/// The permission gate sends the user to System Settings, which takes focus.
/// Without this the instructions would vanish at the moment they are being
/// followed, and the user would return to an empty screen.
#[tauri::command]
pub fn set_dismiss_on_blur(state: State<'_, AppState>, value: bool) {
    state.set_dismiss_on_blur(value);
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
