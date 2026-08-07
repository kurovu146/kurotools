//! The shape every provider returns and the UI renders. Pure data, no I/O.

use serde::Serialize;

/// Hard cap on how much text is sent to a provider in one lookup.
///
/// Inherited from `tl`. Chosen to keep a runaway paste — a whole file selected
/// by accident — from becoming a multi-megabyte request.
pub const MAX_CHARS: usize = 5000;

/// Above this many words, the dictionary lookup is skipped entirely.
///
/// The gtx endpoint returns no dictionary entry for phrases, so the request is
/// pure latency with a guaranteed empty result.
pub const MAX_DEFINITION_WORDS: usize = 4;

/// One sense of a word, as the dictionary reports it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Definition {
    pub part_of_speech: String,
    /// Most words have none. Present for domain-specific senses ("computing",
    /// "law"), which is exactly where a general translation is least reliable.
    pub domain: Option<String>,
    pub gloss: String,
}

/// A completed lookup. Always constructible even when everything failed —
/// `translation: None` with empty `definitions` is the "unavailable" state the
/// UI renders, and it must never surface as an error dialog.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Lookup {
    pub source: String,
    /// Whether [`truncate_source`] cut the text before it was sent.
    ///
    /// Carried as a flag rather than re-derived from `source` later: text that
    /// merely *contains* a truncation marker — pasted output from an earlier
    /// lookup, say — must not be reported as truncated when it never was.
    /// This exact bug shipped in `tl`.
    pub source_truncated: bool,
    pub definitions: Vec<Definition>,
    pub translation: Option<String>,
}

impl Lookup {
    /// A lookup that resolved to nothing. The provider's failure path.
    pub fn unavailable(source: String, source_truncated: bool) -> Self {
        Self {
            source,
            source_truncated,
            definitions: Vec::new(),
            translation: None,
        }
    }

    /// Whitespace-separated word count of the source text.
    pub fn word_count(&self) -> usize {
        self.source.split_whitespace().count()
    }

    /// Whether this input is short enough to be worth a dictionary request.
    pub fn wants_definitions(&self) -> bool {
        self.word_count() <= MAX_DEFINITION_WORDS
    }
}

/// Cap `text` at [`MAX_CHARS`], reporting whether it was cut.
///
/// Counts and slices by **character**, not byte. Slicing a `&str` at an
/// arbitrary byte offset panics when it lands mid-character, and Vietnamese
/// input is multi-byte throughout — so a byte-based cap would both truncate
/// early and eventually panic on real user text.
pub fn truncate_source(text: &str) -> (String, bool) {
    let mut out = String::with_capacity(text.len().min(MAX_CHARS * 4));
    let mut count = 0usize;

    for ch in text.chars() {
        if count == MAX_CHARS {
            return (out, true);
        }
        out.push(ch);
        count += 1;
    }

    (out, false)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lookup_of(source: &str) -> Lookup {
        Lookup::unavailable(source.to_owned(), false)
    }

    #[test]
    fn truncate_source_leaves_short_text_alone() {
        let (out, cut) = truncate_source("hello");
        assert_eq!(out, "hello");
        assert!(!cut);
    }

    #[test]
    fn truncate_source_leaves_text_of_exactly_max_chars_alone() {
        // The boundary: exactly at the cap is not over it, and reporting a cut
        // here would show the user a truncation marker for intact text.
        let exact = "a".repeat(MAX_CHARS);
        let (out, cut) = truncate_source(&exact);
        assert_eq!(out.chars().count(), MAX_CHARS);
        assert!(!cut);
    }

    #[test]
    fn truncate_source_cuts_at_max_chars_and_reports_it() {
        let long = "a".repeat(MAX_CHARS + 100);
        let (out, cut) = truncate_source(&long);
        assert!(cut);
        assert_eq!(out.chars().count(), MAX_CHARS);
    }

    #[test]
    fn truncate_source_counts_characters_not_bytes() {
        // "ề" is 3 bytes. A byte-based implementation would cut this at a
        // third of the intended length, and could panic splitting a character.
        let long = "ề".repeat(MAX_CHARS + 10);
        let (out, cut) = truncate_source(&long);
        assert!(cut);
        assert_eq!(out.chars().count(), MAX_CHARS);
        assert_eq!(out.len(), MAX_CHARS * 3, "should have cut on chars, not bytes");
    }

    #[test]
    fn truncate_source_never_splits_a_multibyte_character() {
        // Push the cut point onto a character boundary that byte-slicing
        // would land inside of. Any panic here is the bug this guards.
        let text = format!("{}ề tail", "x".repeat(MAX_CHARS - 1));
        let (out, cut) = truncate_source(&text);
        assert!(cut);
        assert!(out.ends_with('ề'));
    }

    #[test]
    fn word_count_is_whitespace_separated() {
        assert_eq!(lookup_of("race condition").word_count(), 2);
    }

    #[test]
    fn word_count_ignores_repeated_and_surrounding_whitespace() {
        assert_eq!(lookup_of("  a\t\tb \n").word_count(), 2);
    }

    #[test]
    fn word_count_of_empty_text_is_zero() {
        assert_eq!(lookup_of("   ").word_count(), 0);
    }

    #[test]
    fn short_input_wants_definitions_and_long_input_does_not() {
        assert!(lookup_of("idempotent").wants_definitions());
        assert!(lookup_of("one two three four").wants_definitions());
        assert!(!lookup_of("one two three four five").wants_definitions());
    }

    #[test]
    fn unavailable_carries_the_source_through() {
        let l = Lookup::unavailable("idempotent".into(), true);
        assert_eq!(l.source, "idempotent");
        assert!(l.source_truncated);
        assert!(l.translation.is_none());
        assert!(l.definitions.is_empty());
    }
}
