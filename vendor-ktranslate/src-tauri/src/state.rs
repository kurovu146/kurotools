//! Long-lived app state.

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

use ktranslate_core::store::Store;
use tauri::{AppHandle, Manager};

/// The database, behind a mutex.
///
/// `rusqlite::Connection` is not `Sync`, and this app makes at most one
/// storage call per lookup — a connection pool would be machinery in service
/// of contention that cannot occur.
pub struct AppState {
    pub store: Mutex<Store>,
    dismiss_on_blur: AtomicBool,
}

impl AppState {
    /// Open the database in the platform's app-data directory.
    pub fn new(app: &AppHandle) -> Result<Self, String> {
        let path = default_database_path(app)?;
        let store = Store::open(&path).map_err(|e| format!("{path:?}: {e}"))?;
        Ok(Self {
            store: Mutex::new(store),
            dismiss_on_blur: AtomicBool::new(true),
        })
    }

    /// Whether losing focus should dismiss the window.
    ///
    /// True for the popup, which behaves like any popover. **False while the
    /// permission gate is showing**: that screen's whole job is to send the
    /// user to System Settings, which takes focus — so dismiss-on-blur would
    /// hide the instructions at the exact moment they are needed, and the user
    /// would come back to nothing.
    pub fn dismiss_on_blur(&self) -> bool {
        self.dismiss_on_blur.load(Ordering::Relaxed)
    }

    pub fn set_dismiss_on_blur(&self, value: bool) {
        self.dismiss_on_blur.store(value, Ordering::Relaxed);
    }
}

fn default_database_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("no app data directory: {e}"))?;
    // This path moved with the rename from `tra`: the bundle identifier is
    // what `app_data_dir()` resolves against, so `com.kurovu.tra/tra.db`
    // became `com.kurovu.ktranslate/ktranslate.db`. There is no in-app
    // migration — an existing install keeps its old directory and starts
    // empty here. Only one install ever existed and its database was copied
    // across by hand; if that ever stops being true, this is where a
    // migration would go.
    Ok(dir.join("ktranslate.db"))
}
