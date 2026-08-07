//! `tra-core` — the framework-free core of Tra.
//!
//! Deliberately knows nothing about Tauri, windows, or the frontend. Everything
//! interesting lives here so it can be tested without a GUI harness, and so
//! swapping the desktop shell costs only the shell.
//!
//! `tests/no_tauri_dep.rs` enforces the "no tauri dependency" rule.

pub mod capture;
