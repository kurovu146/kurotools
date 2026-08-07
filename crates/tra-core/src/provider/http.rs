//! The HTTP half of the gtx provider.
//!
//! Split from parsing so the parser stays pure and testable with plain
//! strings, and so this file's tests can point at a local listener rather than
//! the internet.

use std::time::Duration;

use crate::model::{self, Lookup};
use crate::provider::gtx;

/// Per-request budget. Deliberately short: this popup appears in front of
/// someone mid-sentence, and a slow answer is worse than an honest
/// "unavailable" they can dismiss and retry.
const TIMEOUT: Duration = Duration::from_secs(5);

pub struct GtxProvider {
    endpoint: String,
    timeout: Duration,
}

impl Default for GtxProvider {
    fn default() -> Self {
        Self::new()
    }
}

impl GtxProvider {
    pub fn new() -> Self {
        Self {
            endpoint: gtx::DEFAULT_ENDPOINT.to_owned(),
            timeout: TIMEOUT,
        }
    }

    /// Point the provider at a different base URL. The test seam — it is how
    /// the suite runs offline against a local listener.
    pub fn with_endpoint(endpoint: &str) -> Self {
        Self {
            endpoint: endpoint.to_owned(),
            timeout: TIMEOUT,
        }
    }

    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    /// Look `text` up.
    ///
    /// **Never returns `Err`.** Any failure — dead network, timeout, garbage
    /// response, upstream shape change — produces a [`Lookup`] with no
    /// translation and no definitions, which the UI renders as "unavailable".
    /// A popup that appears on a keystroke must never be able to show an error
    /// dialog or, worse, nothing at all.
    pub fn lookup(&self, text: &str) -> Lookup {
        let (source, source_truncated) = model::truncate_source(text);

        if source.trim().is_empty() {
            return Lookup::unavailable(source, source_truncated);
        }

        let wants_definitions = source.split_whitespace().count() <= model::MAX_DEFINITION_WORDS;

        let translation_url = gtx::build_url(&self.endpoint, "auto", "vi", &source, &["t"]);
        let definition_url = wants_definitions
            .then(|| gtx::build_url(&self.endpoint, "en", "en", &source, &["t", "bd", "md"]));

        // Both requests in flight at once, so wall time is one round trip
        // rather than two. std::thread rather than an async runtime: this is
        // two requests, and pulling in tokio to overlap them would be the
        // heavier dependency by far.
        let timeout = self.timeout;
        let translation_handle = std::thread::spawn(move || fetch(&translation_url, timeout));
        let definition_body = definition_url.map(|url| fetch(&url, timeout));

        // A panicking worker must not take the popup with it.
        let translation_body = translation_handle.join().unwrap_or(None);

        Lookup {
            translation: translation_body.as_deref().and_then(gtx::parse_translation),
            definitions: definition_body
                .flatten()
                .as_deref()
                .map(gtx::parse_definitions)
                .unwrap_or_default(),
            source,
            source_truncated,
        }
    }
}

/// GET `url`, returning the body or `None`. Every error collapses to `None` —
/// the caller has exactly one failure behaviour and no use for the distinction.
fn fetch(url: &str, timeout: Duration) -> Option<String> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(timeout))
        .build()
        .into();

    agent.get(url).call().ok()?.body_mut().read_to_string().ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader, Write};
    use std::net::TcpListener;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    fn fixture(name: &str) -> String {
        let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
        std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("fixture {path}: {e}"))
    }

    struct Server {
        base: String,
        definition_hits: Arc<AtomicUsize>,
        translation_hits: Arc<AtomicUsize>,
    }

    /// A real HTTP listener on an ephemeral port, serving the captured
    /// fixtures. No mocking crate, and nothing leaves the machine — but the
    /// code under test still takes its genuine network path.
    fn serve_fixtures() -> Server {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let base = format!("http://{}", listener.local_addr().unwrap());

        let definition_hits = Arc::new(AtomicUsize::new(0));
        let translation_hits = Arc::new(AtomicUsize::new(0));
        let (d, t) = (Arc::clone(&definition_hits), Arc::clone(&translation_hits));

        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { continue };

                let mut request_line = String::new();
                if BufReader::new(&stream)
                    .read_line(&mut request_line)
                    .is_err()
                {
                    continue;
                }

                // `dt=md` is only ever present on the definition request.
                let body = if request_line.contains("dt%3Dmd") || request_line.contains("dt=md") {
                    d.fetch_add(1, Ordering::SeqCst);
                    fixture("def_idempotent.json")
                } else {
                    t.fetch_add(1, Ordering::SeqCst);
                    fixture("tr_sentence.json")
                };

                let _ = write!(
                    stream,
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\
                     Content-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body.len(),
                    body
                );
            }
        });

        Server {
            base,
            definition_hits,
            translation_hits,
        }
    }

    #[test]
    fn lookup_returns_unavailable_when_the_endpoint_is_dead() {
        // Port 1 is reserved and nothing listens there.
        let out = GtxProvider::with_endpoint("http://127.0.0.1:1/translate")
            .with_timeout(Duration::from_millis(300))
            .lookup("idempotent");

        assert_eq!(out.source, "idempotent");
        assert!(out.translation.is_none());
        assert!(out.definitions.is_empty());
    }

    #[test]
    fn lookup_returns_a_translation_and_definitions_for_a_word() {
        let s = serve_fixtures();
        let out = GtxProvider::with_endpoint(&s.base).lookup("idempotent");

        assert!(out.translation.is_some());
        assert!(!out.definitions.is_empty());
        assert_eq!(s.definition_hits.load(Ordering::SeqCst), 1);
        assert_eq!(s.translation_hits.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn lookup_skips_the_definition_request_for_long_phrases() {
        // The endpoint returns no dictionary entry above MAX_DEFINITION_WORDS,
        // so making the request is pure added latency.
        let s = serve_fixtures();
        let out =
            GtxProvider::with_endpoint(&s.base).lookup("this phrase has more than four words");

        assert_eq!(s.definition_hits.load(Ordering::SeqCst), 0);
        assert_eq!(s.translation_hits.load(Ordering::SeqCst), 1);
        assert!(out.definitions.is_empty());
        assert!(out.translation.is_some());
    }

    #[test]
    fn lookup_truncates_oversized_input_and_flags_it() {
        let s = serve_fixtures();
        let out = GtxProvider::with_endpoint(&s.base).lookup(&"a".repeat(model::MAX_CHARS + 50));

        assert!(out.source_truncated);
        assert_eq!(out.source.chars().count(), model::MAX_CHARS);
    }

    #[test]
    fn lookup_of_blank_input_makes_no_request_at_all() {
        let s = serve_fixtures();
        let out = GtxProvider::with_endpoint(&s.base).lookup("   \n\t ");

        assert_eq!(s.translation_hits.load(Ordering::SeqCst), 0);
        assert_eq!(s.definition_hits.load(Ordering::SeqCst), 0);
        assert!(out.translation.is_none());
    }

    /// The only test that touches the network. `#[ignore]`d so the suite stays
    /// offline and deterministic; run it deliberately with
    /// `cargo test -p tra-core -- --ignored` to check whether the unofficial
    /// endpoint still behaves the way the fixtures captured.
    ///
    /// Fixtures prove the parser handles the shapes we recorded. Only this
    /// proves the shapes are still real.
    #[test]
    #[ignore = "hits the live Google endpoint"]
    fn live_endpoint_still_returns_what_the_fixtures_captured() {
        let out = GtxProvider::new().lookup("idempotent");

        assert!(
            out.translation.is_some(),
            "live endpoint returned no translation — it may have changed or rate-limited"
        );
        assert!(
            !out.definitions.is_empty(),
            "live endpoint returned no definitions — index 12 may have moved"
        );
        assert!(out.definitions.iter().all(|d| !d.gloss.is_empty()));
    }

    #[test]
    fn a_garbage_response_yields_unavailable_rather_than_panicking() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());

        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { continue };
                let mut line = String::new();
                let _ = BufReader::new(&stream).read_line(&mut line);
                let body = "not json at all";
                let _ = write!(
                    stream,
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body.len(),
                    body
                );
            }
        });

        let out = GtxProvider::with_endpoint(&base).lookup("idempotent");
        assert!(out.translation.is_none());
        assert!(out.definitions.is_empty());
        assert_eq!(out.source, "idempotent");
    }
}
