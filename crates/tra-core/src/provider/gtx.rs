//! The free Google `gtx` endpoint — parsing only. No I/O lives in this file,
//! so every test here runs offline against captured fixtures.
//!
//! The endpoint is unofficial and undocumented. Its response is a positional
//! JSON array with no field names and inconsistent arity: entries simply stop
//! early when they have nothing more to say. Every index access below is
//! therefore optional, and anything unrecognised is skipped rather than
//! treated as an error — a shape change upstream must degrade to "no result",
//! never to a panic.

use crate::lang::Lang;
use crate::model::Definition;

/// The live endpoint. Overridable per-provider so tests can point at a local
/// listener instead.
pub const DEFAULT_ENDPOINT: &str = "https://translate.googleapis.com/translate_a/single";

/// How many definitions to keep. More than this and the popup becomes a wall
/// of text nobody reads.
pub const MAX_DEFINITIONS: usize = 4;

/// Percent-encode `text` for use in a query string.
///
/// Hand-rolled rather than pulled from a crate because the rule is short and
/// the correctness condition is precise: encode **bytes**, not chars, so UTF-8
/// is preserved exactly. Keeps only the RFC 3986 unreserved set.
pub fn percent_encode(text: &str) -> String {
    fn unreserved(b: u8) -> bool {
        b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~')
    }

    let mut out = String::with_capacity(text.len());
    for &b in text.as_bytes() {
        if unreserved(b) {
            out.push(b as char);
        } else {
            out.push('%');
            out.push_str(&format!("{b:02X}"));
        }
    }
    out
}

/// Build a request URL.
///
/// Each entry in `dts` becomes one `&dt=` parameter, which is how the endpoint
/// selects what to return: `t` translation, `bd` dictionary, `md` definitions.
pub fn build_url(endpoint: &str, sl: &str, tl: &str, text: &str, dts: &[&str]) -> String {
    let mut url = format!("{endpoint}?client=gtx&sl={sl}&tl={tl}");
    for dt in dts {
        url.push_str("&dt=");
        url.push_str(dt);
    }
    url.push_str("&q=");
    url.push_str(&percent_encode(text));
    url
}

/// Extract the translated text.
///
/// The endpoint splits input into per-sentence chunks at `[0][*][0]`. They
/// must be **joined** — reading only the first chunk silently drops everything
/// after the first sentence, which is not visibly broken and so is easy to
/// ship.
pub fn parse_translation(json: &str) -> Option<String> {
    let root: serde_json::Value = serde_json::from_str(json).ok()?;
    let chunks = root.get(0)?.as_array()?;

    let mut out = String::new();
    for chunk in chunks {
        if let Some(part) = chunk.get(0).and_then(|v| v.as_str()) {
            out.push_str(part);
        }
    }

    if out.trim().is_empty() {
        None
    } else {
        Some(out)
    }
}

/// Extract dictionary definitions, capped at [`MAX_DEFINITIONS`].
pub fn parse_definitions(json: &str) -> Vec<Definition> {
    parse_definitions_capped(json, MAX_DEFINITIONS)
}

/// Extract dictionary definitions, capped at `cap`.
///
/// The cap is a parameter rather than only a constant so the cap itself is
/// testable. A test asserting `len() <= MAX_DEFINITIONS` against a fixture
/// with fewer entries than the cap passes no matter what the code does; being
/// able to lower the cap makes that test bite.
///
/// Shape at index 12:
/// `[[part_of_speech, [[gloss, id, null, [_, _, [domain]]], ...], word, rank], ...]`
///
/// Everything from `id` onwards is frequently absent, and index 3 has at least
/// two observed shapes — `[null, null, ["Mathematics"]]` carrying a domain, and
/// `[["archaic"]]` carrying a register label instead. Only the former is a
/// domain, so the lookup is specifically `[3][2][0]` and anything else reads
/// as "no domain".
pub fn parse_definitions_capped(json: &str, cap: usize) -> Vec<Definition> {
    let Ok(root) = serde_json::from_str::<serde_json::Value>(json) else {
        return Vec::new();
    };
    let Some(groups) = root.get(12).and_then(|v| v.as_array()) else {
        return Vec::new();
    };

    let mut out = Vec::new();

    for group in groups {
        let part_of_speech = group
            .get(0)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_owned();

        let Some(senses) = group.get(1).and_then(|v| v.as_array()) else {
            continue;
        };

        for sense in senses {
            if out.len() == cap {
                return out;
            }

            let Some(gloss) = sense.get(0).and_then(|v| v.as_str()) else {
                continue;
            };
            if gloss.trim().is_empty() {
                continue;
            }

            let domain = sense
                .get(3)
                .and_then(|v| v.get(2))
                .and_then(|v| v.get(0))
                .and_then(|v| v.as_str())
                .map(|s| s.to_owned());

            out.push(Definition {
                part_of_speech: part_of_speech.clone(),
                domain,
                gloss: gloss.to_owned(),
            });
        }
    }

    out
}

/// The language the endpoint says it detected, at index `[2]`.
///
/// **Only ever used to label the result.** Measured on single words this is
/// wrong roughly half the time — `idempotent` reports `la`, `Haus` reports
/// `en` — so choosing a request from it would break the definition pane for
/// exactly the inputs a lookup popup receives. Codes outside [`SUPPORTED`]
/// map to `None` so nothing unvalidated can reach a URL.
///
/// [`SUPPORTED`]: crate::lang::SUPPORTED
pub fn parse_detected(json: &str) -> Option<Lang> {
    let root: serde_json::Value = serde_json::from_str(json).ok()?;
    Lang::from_code(root.get(2)?.as_str()?)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> String {
        let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
        std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("fixture {path}: {e}"))
    }

    // -- translation --------------------------------------------------------

    #[test]
    fn parses_a_single_sentence_translation() {
        let out = parse_translation(&fixture("tr_sentence.json")).unwrap();
        assert!(!out.trim().is_empty());
    }

    #[test]
    fn joins_every_chunk_of_a_multi_sentence_translation() {
        // The whole point: this fixture has 3 chunks. Reading only the first
        // loses two thirds of the translation without looking broken.
        let out = parse_translation(&fixture("tr_multichunk.json")).unwrap();
        assert!(out.contains("Kết quả"), "second chunk missing from: {out}");
        assert!(out.contains("tái tạo"), "third chunk missing from: {out}");
    }

    #[test]
    fn malformed_json_yields_no_translation_rather_than_panicking() {
        assert!(parse_translation(&fixture("malformed.json")).is_none());
    }

    #[test]
    fn an_empty_response_yields_no_translation() {
        assert!(parse_translation("[]").is_none());
        assert!(parse_translation("[[]]").is_none());
    }

    // -- definitions --------------------------------------------------------

    #[test]
    fn parses_definitions_with_part_of_speech_and_gloss() {
        let defs = parse_definitions(&fixture("def_idempotent.json"));
        assert!(!defs.is_empty());
        assert!(defs.iter().all(|d| !d.part_of_speech.is_empty()));
        assert!(defs.iter().all(|d| !d.gloss.is_empty()));
    }

    #[test]
    fn reads_the_domain_when_one_is_present() {
        let defs = parse_definitions(&fixture("def_idempotent.json"));
        assert_eq!(defs[0].domain.as_deref(), Some("Mathematics"));
    }

    #[test]
    fn handles_senses_with_no_domain_at_all() {
        // throttle's first sense stops at [gloss, id] — index 3 is absent.
        let defs = parse_definitions(&fixture("def_throttle.json"));
        assert!(defs.iter().any(|d| d.domain.is_none()));
        assert!(defs.iter().all(|d| !d.gloss.is_empty()));
    }

    #[test]
    fn does_not_mistake_a_register_label_for_a_domain() {
        // throttle's "a throat, gullet, or windpipe" carries [["archaic"]] at
        // index 3 — a register label, not a domain. Reading [3][0][0] instead
        // of [3][2][0] would surface "archaic" as though it were a subject area.
        let defs = parse_definitions(&fixture("def_throttle.json"));
        assert!(
            defs.iter().all(|d| d.domain.as_deref() != Some("archaic")),
            "a register label leaked into the domain field: {defs:?}"
        );
    }

    #[test]
    fn returns_nothing_when_the_response_has_no_definitions() {
        // kubectl: the response has only 8 elements, so index 12 is absent.
        assert!(parse_definitions(&fixture("def_empty.json")).is_empty());
    }

    #[test]
    fn malformed_json_yields_no_definitions_rather_than_panicking() {
        assert!(parse_definitions(&fixture("malformed.json")).is_empty());
    }

    #[test]
    fn definitions_are_capped_and_the_cap_is_load_bearing() {
        // Asserting only `<= MAX_DEFINITIONS` would pass regardless of the
        // code whenever the fixture yields fewer entries than the cap. Driving
        // the cap down and asserting the exact count makes it bite.
        let json = fixture("def_throttle.json");
        assert_eq!(parse_definitions_capped(&json, 1).len(), 1);
        assert_eq!(parse_definitions_capped(&json, 2).len(), 2);
        assert!(parse_definitions_capped(&json, MAX_DEFINITIONS).len() <= MAX_DEFINITIONS);
    }

    #[test]
    fn a_cap_of_zero_yields_nothing() {
        assert!(parse_definitions_capped(&fixture("def_throttle.json"), 0).is_empty());
    }

    // -- urls ---------------------------------------------------------------

    #[test]
    fn percent_encodes_non_ascii_as_utf8_bytes() {
        // "đ" is U+0111 = 0xC4 0x91 in UTF-8. Encoding chars rather than bytes
        // would produce mojibake at the far end.
        assert_eq!(percent_encode("đ"), "%C4%91");
    }

    #[test]
    fn percent_encoding_leaves_the_unreserved_set_alone() {
        assert_eq!(percent_encode("aZ0-_.~"), "aZ0-_.~");
    }

    #[test]
    fn percent_encoding_escapes_characters_that_would_break_the_query() {
        assert_eq!(percent_encode("a b&c=d?e#f"), "a%20b%26c%3Dd%3Fe%23f");
    }

    #[test]
    fn build_url_assembles_every_dt_parameter() {
        let url = build_url("https://x/y", "en", "en", "cat", &["t", "bd", "md"]);
        assert!(url.starts_with("https://x/y?client=gtx&sl=en&tl=en"));
        assert!(url.contains("&dt=t"));
        assert!(url.contains("&dt=bd"));
        assert!(url.contains("&dt=md"));
        assert!(url.ends_with("&q=cat"));
    }

    #[test]
    fn build_url_never_leaves_a_raw_space_in_the_query() {
        let url = build_url("https://x/y", "auto", "vi", "điều kiện", &["t"]);
        assert!(!url.contains(' '), "unencoded space in {url}");
        assert!(url.contains("%C4%91"));
    }

    // -- detected language --------------------------------------------------

    #[test]
    fn parse_detected_reads_the_language_code() {
        assert_eq!(
            parse_detected(r#"[[["x","y",null,null,1]],null,"de"]"#),
            Lang::from_code("de")
        );
    }

    #[test]
    fn parse_detected_maps_an_unsupported_code_to_none() {
        // The endpoint has answered with codes outside its own accepted set.
        // Anything the table does not know must not reach a URL.
        assert_eq!(parse_detected(r#"[[["x","y"]],null,"xx-YY"]"#), None);
    }

    #[test]
    fn parse_detected_tolerates_a_missing_or_malformed_field() {
        assert_eq!(parse_detected("[[]]"), None);
        assert_eq!(parse_detected(r#"[[],null,7]"#), None);
        assert_eq!(parse_detected("not json at all"), None);
    }

    #[test]
    fn parse_detected_reads_latin_from_the_real_idempotent_response() {
        // The measured case that rules out driving the definition pane from
        // detection: this is a genuine capture, and `la` is what it says.
        let detected = parse_detected(&fixture("auto_la_idempotent.json"));
        assert_eq!(detected, Lang::from_code("la"));
    }
}
