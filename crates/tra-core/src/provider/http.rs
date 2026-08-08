//! The HTTP half of the gtx provider.
//!
//! Split from parsing so the parser stays pure and testable with plain
//! strings, and so this file's tests can point at a local listener rather than
//! the internet.

use std::time::Duration;

use crate::config::LangConfig;
use crate::lang::Lang;
use crate::model::{self, Definition, Lookup};
use crate::provider::gtx;
use crate::provider::plan::{self, FirstPass, Request};

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

    /// Look `text` up under `config`.
    ///
    /// **Never returns `Err`.** Any failure — dead network, timeout, garbage
    /// response, upstream shape change — produces a [`Lookup`] with no
    /// translation and no definitions, which the UI renders as "unavailable".
    /// A popup that appears on a keystroke must never be able to show an error
    /// dialog or, worse, nothing at all.
    ///
    /// Decides nothing about languages: [`plan`] says which requests a lookup
    /// needs, this runs them and labels the result.
    pub fn lookup(&self, text: &str, config: &LangConfig) -> Lookup {
        let (source, source_truncated) = model::truncate_source(text);

        let Some(initial) = plan::initial_request(config, &source) else {
            return Lookup::unavailable(source, source_truncated, config.target());
        };

        let body = self.fetch(&initial, &source);
        let first = FirstPass {
            // A response that arrived and said nothing looks identical to no
            // response at all once parsed, and the planner has to tell them
            // apart to avoid spending a second timeout on a dead endpoint.
            responded: body.is_some(),
            detected: body.as_deref().and_then(gtx::parse_detected),
            translation: body.as_deref().and_then(gtx::parse_translation),
            definitions: body
                .as_deref()
                .map(gtx::parse_definitions)
                .unwrap_or_default(),
        };

        let followups = plan::followups(config, &source, &first);

        // Which language the fallback dictionary is being asked in, read off
        // the planned request rather than assumed. After an echo the planner
        // asks the *target* dictionary — the echo is the endpoint saying the
        // text is already in the target — so `config.other()` would mislabel
        // exactly the case the follow-up exists to rescue. Taken here, before
        // the request is moved into the worker below.
        let fallback_lang = followups
            .definition
            .as_ref()
            .and_then(|request| Lang::from_code(&request.sl));

        // Both follow-ups are independent, so wall time stays one extra round
        // trip rather than two. std::thread rather than an async runtime: this
        // is at most two requests, and pulling in tokio to overlap them would
        // be the heavier dependency by far.
        let definition_handle = followups.definition.map(|request| {
            let (endpoint, timeout, text) = (self.endpoint.clone(), self.timeout, source.clone());
            std::thread::spawn(move || {
                let url = gtx::build_url(&endpoint, &request.sl, &request.tl, &text, &request.dts);
                fetch(&url, timeout)
            })
        });

        let retranslation = followups
            .retranslate
            .and_then(|request| self.fetch(&request, &source));

        // A panicking worker must not take the popup with it.
        let fallback_definitions: Vec<Definition> = definition_handle
            .and_then(|handle| handle.join().unwrap_or(None))
            .as_deref()
            .map(gtx::parse_definitions)
            .unwrap_or_default();

        let retried = retranslation.as_deref().and_then(gtx::parse_translation);

        // Which language the definitions ended up being written in. The first
        // pass defines in the source language (explicit, or whatever detection
        // reported); the follow-up defines in whichever language it asked.
        let (definitions, definition_lang) = if !first.definitions.is_empty() {
            (first.definitions, config.source().or(first.detected))
        } else if !fallback_definitions.is_empty() {
            (fallback_definitions, fallback_lang)
        } else {
            (Vec::new(), None)
        };

        let (translation, used_retry) =
            match plan::resolve_translation(&source, first.translation, retried) {
                Some((text, used_retry)) => (Some(text), used_retry),
                None => (None, false),
            };

        Lookup {
            translation,
            definitions,
            definition_lang,
            source_lang: config.source().or(first.detected),
            target_lang: if used_retry {
                config.other()
            } else {
                config.target()
            },
            source,
            source_truncated,
        }
    }

    /// Run one planned request against this provider's endpoint.
    fn fetch(&self, request: &Request, text: &str) -> Option<String> {
        let url = gtx::build_url(&self.endpoint, &request.sl, &request.tl, text, &request.dts);
        fetch(&url, self.timeout)
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
    use std::sync::{Arc, Mutex};

    fn fixture(name: &str) -> String {
        let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
        std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("fixture {path}: {e}"))
    }

    struct Server {
        base: String,
        /// Every request line the server saw, in order. Richer than a counter:
        /// the tests assert on *which* requests were made, not just how many.
        seen: Arc<Mutex<Vec<String>>>,
    }

    impl Server {
        fn count(&self) -> usize {
            self.seen.lock().unwrap().len()
        }

        fn saw(&self, needle: &str) -> bool {
            self.seen
                .lock()
                .unwrap()
                .iter()
                .any(|line| line.contains(needle))
        }

        /// The request lines, for assertion messages.
        fn lines(&self) -> Vec<String> {
            self.seen.lock().unwrap().clone()
        }
    }

    /// A real HTTP listener on an ephemeral port, answering from the captured
    /// fixtures according to the `sl`/`tl` pair it was asked for. Nothing leaves
    /// the machine, but the code under test still takes its genuine network path.
    fn serve_fixtures() -> Server {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let base = format!("http://{}", listener.local_addr().unwrap());
        let seen = Arc::new(Mutex::new(Vec::new()));
        let log = Arc::clone(&seen);

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
                log.lock().unwrap().push(request_line.clone());

                // The endpoint returns the `md` section only when `dt=md` was
                // asked for — every captured fixture without it lacks index 12.
                // The stub has to honour that: a server that hands back
                // definitions nobody requested lets a plan that stopped asking
                // for them still look correct.
                let asked_for_md = request_line.contains("dt=md");

                // Order matters. The plain `tl=en` arm must come before the
                // identical-output arm: the no-op retry targets English and has
                // to answer with something *different*, or the retry looks like
                // another no-op and the test proves nothing.
                let body = if request_line.contains("sl=de") && asked_for_md {
                    fixture("def_haus_de.json")
                } else if request_line.contains("sl=en&tl=en") && asked_for_md {
                    fixture("def_idempotent.json")
                } else if request_line.contains("tl=en") && asked_for_md {
                    // An English target that comes back echoed: detection said
                    // Latin, so no `md` arrived and the text is proof of nothing
                    // except that it is already English. The retry below never
                    // asks for `md`, so it cannot land here.
                    fixture("auto_en_idempotent.json")
                } else if request_line.contains("tl=en") {
                    fixture("tr_sentence.json")
                } else if request_line.contains("Freiheit") && asked_for_md {
                    fixture("auto_freiheit_de.json")
                } else if request_line.contains("m%C3%A8o") {
                    // "con mèo đang ngủ", percent-encoded by `gtx::percent_encode`.
                    fixture("tr_identical.json")
                } else {
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

        Server { base, seen }
    }

    /// A listener that accepts, logs, and hangs up without answering. What a
    /// dead endpoint looks like to `fetch` — a request that yields no body —
    /// but countable, and without making the suite wait out a real timeout.
    fn serve_silence() -> Server {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let base = format!("http://{}", listener.local_addr().unwrap());
        let seen = Arc::new(Mutex::new(Vec::new()));
        let log = Arc::clone(&seen);

        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(stream) = stream else { continue };

                let mut request_line = String::new();
                if BufReader::new(&stream)
                    .read_line(&mut request_line)
                    .is_err()
                {
                    continue;
                }
                log.lock().unwrap().push(request_line);
                // Dropped here, unanswered.
            }
        });

        Server { base, seen }
    }

    fn auto_vi() -> LangConfig {
        LangConfig::default()
    }

    fn de_vi() -> LangConfig {
        LangConfig::new(Lang::from_code("de"), Lang::VI, Lang::EN)
    }

    #[test]
    fn lookup_returns_unavailable_when_the_endpoint_is_dead() {
        // Port 1 is reserved and nothing listens there.
        let out = GtxProvider::with_endpoint("http://127.0.0.1:1/translate")
            .with_timeout(Duration::from_millis(300))
            .lookup("idempotent", &auto_vi());

        assert_eq!(out.source, "idempotent");
        assert!(out.translation.is_none());
        assert!(out.definitions.is_empty());
        assert_eq!(
            out.target_lang,
            Lang::VI,
            "a failed lookup still reports what it aimed at"
        );
    }

    #[test]
    fn a_first_request_that_never_answers_is_not_followed_by_a_second() {
        // The timeout budget is per request, so a follow-up fired at an
        // endpoint that just failed to answer doubles how long the popup shows
        // nothing — five seconds becomes ten. `idempotent` is the input that
        // would otherwise plan the fallback-dictionary request.
        let s = serve_silence();
        let out = GtxProvider::with_endpoint(&s.base).lookup("idempotent", &auto_vi());

        assert_eq!(s.count(), 1, "requests made: {:?}", s.lines());
        assert!(out.translation.is_none());
        assert!(out.definitions.is_empty());
        assert_eq!(out.source, "idempotent");
    }

    #[test]
    fn an_explicit_source_costs_exactly_one_request() {
        // The latency claim. The old build made two requests for this.
        let s = serve_fixtures();
        let out = GtxProvider::with_endpoint(&s.base).lookup("Haus", &de_vi());

        assert_eq!(s.count(), 1, "requests made: {:?}", s.lines());
        assert!(out.translation.is_some());
        assert!(!out.definitions.is_empty());
        assert_eq!(out.definition_lang, Lang::from_code("de"));
        assert_eq!(out.source_lang, Lang::from_code("de"));
    }

    #[test]
    fn an_auto_source_with_no_definition_asks_the_fallback_dictionary() {
        // The `idempotent` rescue path.
        let s = serve_fixtures();
        let out = GtxProvider::with_endpoint(&s.base).lookup("idempotent", &auto_vi());

        assert!(s.saw("sl=en&tl=en"), "requests made: {:?}", s.lines());
        assert!(!out.definitions.is_empty());
        assert_eq!(out.definition_lang, Some(Lang::EN));
    }

    #[test]
    fn an_echoed_first_pass_takes_its_definition_from_the_target_not_the_fallback() {
        // Auto into English, falling back to Vietnamese. The first pass hands
        // the text straight back, which is the endpoint saying it is already
        // English, so the dictionary to ask is English — the *target*. Reading
        // the label off `other` instead would file an English gloss under
        // Vietnamese, and the retry here really does move the target to
        // Vietnamese, so the two are not interchangeable.
        let s = serve_fixtures();
        let config = LangConfig::new(None, Lang::EN, Lang::VI);
        let out = GtxProvider::with_endpoint(&s.base).lookup("idempotent", &config);

        assert!(s.saw("sl=en&tl=en"), "requests made: {:?}", s.lines());
        assert!(!out.definitions.is_empty());
        assert_eq!(out.definition_lang, Some(Lang::EN));
        assert_eq!(out.target_lang, Lang::VI, "the retry moved the target");

        // The two labels disagree, on purpose and by different routes:
        // `source_lang` is whatever detection claimed (F2: `idempotent` reports
        // Latin), while `definition_lang` comes from the echo, which is a fact
        // about the response rather than a guess about the input. So the UI
        // labels the source pane "Latin" and the definition pane "English" for
        // one word. Pinned rather than fixed — the echo is the more reliable
        // of the two, and overwriting `source_lang` with it would throw away
        // what the endpoint actually said.
        assert_eq!(
            out.source_lang,
            Lang::from_code("la"),
            "detection is reported verbatim, even when the echo disagrees"
        );
    }

    #[test]
    fn an_auto_source_labels_the_definition_with_the_detected_language() {
        // When detection is confident the first request returns `md` as well — a
        // definition in a language the old build could not produce at all.
        let s = serve_fixtures();
        let out = GtxProvider::with_endpoint(&s.base).lookup("Freiheit", &auto_vi());

        assert_eq!(s.count(), 1, "requests made: {:?}", s.lines());
        assert!(!out.definitions.is_empty());
        assert_eq!(out.definition_lang, Lang::from_code("de"));
        assert_eq!(out.source_lang, Lang::from_code("de"));
    }

    #[test]
    fn an_identical_translation_is_retried_into_the_other_language() {
        let s = serve_fixtures();
        // The exact text `tr_identical.json` echoes back — that is what makes it
        // a no-op. The retry targets English and gets a different answer.
        let out = GtxProvider::with_endpoint(&s.base).lookup("con mèo đang ngủ", &auto_vi());

        assert!(s.saw("tl=en"), "requests made: {:?}", s.lines());
        assert_eq!(
            out.target_lang,
            Lang::EN,
            "the UI must label the language actually used"
        );
        assert_ne!(
            out.translation.as_deref(),
            Some("con mèo đang ngủ"),
            "invariant 1: a lookup must never echo its input back"
        );
        // An echo is the endpoint saying the text is already in the target, so
        // the dictionary to ask is the *target*, not the fallback. Asserting on
        // the request rather than the answer because the endpoint has no
        // Vietnamese dictionary to answer with.
        assert!(
            s.saw("sl=vi&tl=vi"),
            "the echo must send the definition follow-up to the target dictionary, \
             not the fallback: {:?}",
            s.lines()
        );
    }

    #[test]
    fn lookup_skips_the_definition_request_for_long_phrases() {
        // The endpoint returns no dictionary entry above MAX_DEFINITION_WORDS,
        // so making the request is pure added latency.
        let s = serve_fixtures();
        let out = GtxProvider::with_endpoint(&s.base)
            .lookup("this phrase has more than four words", &auto_vi());

        assert_eq!(s.count(), 1, "requests made: {:?}", s.lines());
        assert!(out.definitions.is_empty());
        assert!(out.translation.is_some());
    }

    #[test]
    fn lookup_truncates_oversized_input_and_flags_it() {
        let s = serve_fixtures();
        let out = GtxProvider::with_endpoint(&s.base)
            .lookup(&"a".repeat(model::MAX_CHARS + 50), &auto_vi());

        assert!(out.source_truncated);
        assert_eq!(out.source.chars().count(), model::MAX_CHARS);
    }

    #[test]
    fn lookup_of_blank_input_makes_no_request_at_all() {
        let s = serve_fixtures();
        let out = GtxProvider::with_endpoint(&s.base).lookup("   \n\t ", &auto_vi());

        assert_eq!(s.count(), 0, "requests made: {:?}", s.lines());
        assert!(out.translation.is_none());
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

        let out = GtxProvider::with_endpoint(&base).lookup("idempotent", &auto_vi());
        assert!(out.translation.is_none());
        assert!(out.definitions.is_empty());
        assert_eq!(out.source, "idempotent");
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
        let out = GtxProvider::new().lookup("idempotent", &auto_vi());
        assert!(
            out.translation.is_some(),
            "live endpoint returned no translation"
        );
        assert!(
            !out.definitions.is_empty(),
            "live endpoint returned no definitions"
        );
        // Definitions arriving is not the same as definitions being readable:
        // an upstream move of the gloss field would return the right number of
        // empty entries, and nothing else in the suite would notice.
        assert!(out.definitions.iter().all(|d| !d.gloss.is_empty()));

        // A non-English pair, so per-language drift surfaces too. This is the
        // measured F1 claim: one request, both panes, gloss in German.
        let de = GtxProvider::new().lookup("Haus", &de_vi());
        assert!(
            de.translation.is_some(),
            "live endpoint returned no de->vi translation"
        );
        assert!(
            !de.definitions.is_empty(),
            "live endpoint returned no German definitions"
        );
        assert_eq!(de.definition_lang, Lang::from_code("de"));
    }
}
