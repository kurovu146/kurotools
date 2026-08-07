//! Long-lived app state.

use std::path::PathBuf;
use std::sync::Mutex;

use tauri::{AppHandle, Manager};
use tra_core::store::Store;

/// The database, behind a mutex.
///
/// `rusqlite::Connection` is not `Sync`, and this app makes at most one
/// storage call per lookup — a connection pool would be machinery in service
/// of contention that cannot occur.
pub struct AppState {
    pub store: Mutex<Store>,
}

impl AppState {
    /// Open the database in the platform's app-data directory.
    pub fn new(app: &AppHandle) -> Result<Self, String> {
        let path = default_database_path(app)?;
        let store = Store::open(&path).map_err(|e| format!("{path:?}: {e}"))?;
        Ok(Self {
            store: Mutex::new(store),
        })
    }
}

fn default_database_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("no app data directory: {e}"))?;
    Ok(dir.join("tra.db"))
}
