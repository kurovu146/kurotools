//! The IPC surface. Thin by design — every command here should be a couple of
//! lines that hand off to `tra-core`, so the logic stays testable without a
//! GUI and the shell stays swappable.

use tra_core::model::Lookup;
use tra_core::provider::GtxProvider;

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
