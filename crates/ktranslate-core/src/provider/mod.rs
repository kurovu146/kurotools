//! Lookup sources.
//!
//! Everything that can answer "what does this mean" sits behind this module so
//! adding a source — a different dictionary, or the AI provider planned for
//! v2 — is a new file here rather than branching scattered through the app.

pub mod gtx;
pub mod http;
pub mod plan;

pub use http::GtxProvider;
