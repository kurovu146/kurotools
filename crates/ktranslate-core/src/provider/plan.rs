//! What requests a lookup needs — decided without touching the network.
//!
//! Kept pure and separate from [`super::http`] so the branching that actually
//! matters can be tested exhaustively rather than through a fixture server.
//! `GtxProvider` executes what this module describes and makes no decisions of
//! its own.

use crate::config::LangConfig;
use crate::lang::Lang;
use crate::model::{self, Definition};

/// One request to the endpoint, minus the text and the base URL.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Request {
    pub sl: String,
    pub tl: String,
    /// Which sections to ask for: `t` translation, `md` definitions.
    pub dts: Vec<&'static str>,
}

/// What the first response yielded. The pure input to [`followups`].
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct FirstPass {
    /// Whether a response arrived at all.
    ///
    /// Distinct from "arrived but said nothing useful". Every field below is
    /// empty in both cases, so without this flag the planner cannot tell a
    /// dead network from a word with no dictionary entry — and would answer
    /// the first by spending a second timeout to learn the same thing.
    pub responded: bool,
    pub detected: Option<Lang>,
    pub translation: Option<String>,
    pub definitions: Vec<Definition>,
}

/// The conditional second round. Both entries are independent and may run
/// concurrently.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Followups {
    /// A dictionary request, when the first pass produced no definitions and
    /// the source was auto. In `target` when the first pass echoed the input
    /// — that echo is proof the text is already in `target` — and in the
    /// fallback language otherwise.
    pub definition: Option<Request>,
    /// A re-translation into the fallback language, when the first pass came
    /// back as a no-op and the fallback is not itself the source.
    pub retranslate: Option<Request>,
}

/// The request every lookup starts with. `None` for blank input, which is
/// worth no request at all.
pub fn initial_request(config: &LangConfig, source: &str) -> Option<Request> {
    if source.trim().is_empty() {
        return None;
    }

    let mut dts = vec!["t"];
    if model::wants_definitions(source) {
        // F1: with an explicit `sl` this returns the source-language
        // definition on the same round trip. With `sl=auto` it returns one
        // only when detection was confident, which is a free win when it
        // happens and costs nothing when it does not.
        dts.push("md");
    }

    Some(Request {
        sl: config.sl().to_owned(),
        tl: config.target().code().to_owned(),
        dts,
    })
}

/// What still needs asking after the first response.
pub fn followups(config: &LangConfig, source: &str, first: &FirstPass) -> Followups {
    // Nothing came back, so there is nothing to rescue. Both follow-ups below
    // are answers to a *specific* shortcoming of a response that arrived; with
    // no response they would fire into the same dead endpoint and spend a
    // second full timeout to learn what the first already established. The
    // popup would show nothing for twice as long, and this file's whole
    // premise is that a slow answer is worse than an honest "unavailable".
    if !first.responded {
        return Followups::default();
    }

    let echoed = is_no_op(source, first.translation.as_deref());

    // Only when the source was auto. With `sl` pinned, an empty `md` means
    // the word has no dictionary entry — asking a second language would
    // define the text as though it were written in a language it is not.
    let definition = (config.source().is_none()
        && first.definitions.is_empty()
        && model::wants_definitions(source))
    .then(|| {
        // An echoed translation is the response saying the text is already in
        // `target`, so that is the dictionary to ask. Only when the response
        // said nothing about the source is the fallback the best guess —
        // asking `other` after an echo would query the one language the
        // response just ruled out.
        let lang = if echoed {
            config.target()
        } else {
            config.other()
        };
        Request {
            sl: lang.code().to_owned(),
            tl: lang.code().to_owned(),
            dts: vec!["md"],
        }
    });

    // `source == other` survives `LangConfig::new` — it repairs collisions
    // with `target`, not between these two. Retrying into the source language
    // would be an `sl == tl` request, which F4 says returns the input
    // unchanged: a guaranteed-wasted round trip.
    let worth_retrying = echoed && config.source() != Some(config.other());
    let retranslate = worth_retrying.then(|| Request {
        sl: config.sl().to_owned(),
        tl: config.other().code().to_owned(),
        dts: vec!["t"],
    });

    Followups {
        definition,
        retranslate,
    }
}

/// Whether a translation carried no information.
///
/// The endpoint returns the input unchanged, with no error, when the target
/// is the language the text is already in. Tested on the **output** rather
/// than by comparing the detected language to the target, because detection
/// lies: `idempotent` into English reports `la`, so a `detected == target`
/// rule misses it entirely while the text still comes back verbatim.
pub fn is_no_op(source: &str, translation: Option<&str>) -> bool {
    matches!(translation, Some(t) if t.trim() == source.trim())
}

/// Pick the translation to report, and say whether the retry produced it.
///
/// Upholds the invariant that a lookup never echoes its input: if neither the
/// first pass nor the retry produced something different, the honest answer is
/// "unavailable" rather than handing back the text the user already had.
pub fn resolve_translation(
    source: &str,
    first: Option<String>,
    retry: Option<String>,
) -> Option<(String, bool)> {
    match first {
        Some(t) if !is_no_op(source, Some(&t)) => return Some((t, false)),
        _ => {}
    }
    match retry {
        Some(t) if !is_no_op(source, Some(&t)) => Some((t, true)),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lang(code: &str) -> Lang {
        Lang::from_code(code).expect("test uses a supported code")
    }

    /// A first pass that **responded**. Every case below except the dead-network
    /// one is about what a response contained, so responding is the default and
    /// silence is opted into explicitly.
    fn first_pass(translation: Option<&str>, definitions: usize) -> FirstPass {
        FirstPass {
            responded: true,
            detected: None,
            translation: translation.map(str::to_owned),
            definitions: (0..definitions)
                .map(|_| Definition {
                    part_of_speech: "noun".into(),
                    domain: None,
                    gloss: "a gloss".into(),
                })
                .collect(),
        }
    }

    // -- the initial request --------------------------------------------

    #[test]
    fn an_explicit_source_asks_for_the_translation_and_the_definition_at_once() {
        // Measured fact F1: `md` comes back in the source language even when
        // sl != tl, so one request serves both panes.
        let c = LangConfig::new(Some(lang("de")), Lang::VI, Lang::EN);
        let r = initial_request(&c, "Haus").unwrap();
        assert_eq!(r.sl, "de");
        assert_eq!(r.tl, "vi");
        assert_eq!(r.dts, vec!["t", "md"]);
    }

    #[test]
    fn an_auto_source_sends_auto() {
        let r = initial_request(&LangConfig::default(), "Haus").unwrap();
        assert_eq!(r.sl, "auto");
        assert_eq!(r.tl, "vi");
    }

    #[test]
    fn a_long_phrase_skips_the_dictionary_section() {
        // The endpoint returns no dictionary entry above four words, so asking
        // is pure latency with a guaranteed empty result.
        let r = initial_request(
            &LangConfig::default(),
            "this phrase has more than four words",
        )
        .unwrap();
        assert_eq!(r.dts, vec!["t"]);
    }

    #[test]
    fn blank_input_plans_no_request_at_all() {
        assert!(initial_request(&LangConfig::default(), "   \n\t ").is_none());
    }

    #[test]
    fn no_request_ever_asks_for_the_dead_bd_section() {
        // dt=bd returned nothing on every same-language probe, including
        // en->en. The old code asked for it on every definition request.
        let c = LangConfig::new(Some(lang("de")), Lang::VI, Lang::EN);
        let r = initial_request(&c, "Haus").unwrap();
        assert!(!r.dts.contains(&"bd"));
    }

    // -- follow-ups ------------------------------------------------------

    #[test]
    fn auto_with_no_definition_falls_back_to_the_other_language() {
        // The `idempotent` rescue: detection said Latin, no md came back, so
        // ask the fallback language's dictionary.
        let c = LangConfig::default();
        let f = followups(&c, "idempotent", &first_pass(Some("bình thường"), 0));
        let d = f.definition.expect("expected a definition follow-up");
        assert_eq!(d.sl, "en");
        assert_eq!(d.tl, "en");
        assert_eq!(d.dts, vec!["md"]);
    }

    #[test]
    fn an_explicit_source_never_asks_a_second_dictionary() {
        // With sl pinned, an empty md means "this word has no entry" — asking
        // the fallback language would define the word as if it were written
        // in a language it is not.
        let c = LangConfig::new(Some(lang("de")), Lang::VI, Lang::EN);
        let f = followups(&c, "Bäckerei", &first_pass(Some("Tiệm bánh"), 0));
        assert!(f.definition.is_none());
    }

    #[test]
    fn a_definition_already_in_hand_needs_no_follow_up() {
        let f = followups(
            &LangConfig::default(),
            "ephemeral",
            &first_pass(Some("phù du"), 2),
        );
        assert!(f.definition.is_none());
    }

    #[test]
    fn a_long_phrase_never_triggers_a_definition_follow_up() {
        let f = followups(
            &LangConfig::default(),
            "this phrase has more than four words",
            &first_pass(Some("một câu"), 0),
        );
        assert!(f.definition.is_none());
    }

    #[test]
    fn an_identical_translation_triggers_a_retry_into_the_other_language() {
        let f = followups(
            &LangConfig::default(),
            "con mèo",
            &first_pass(Some("con mèo"), 0),
        );
        let r = f.retranslate.expect("expected a retranslate follow-up");
        assert_eq!(r.tl, "en");
        assert_eq!(r.dts, vec!["t"]);
    }

    #[test]
    fn a_useful_translation_triggers_no_retry() {
        let f = followups(
            &LangConfig::default(),
            "idempotent",
            &first_pass(Some("bình thường"), 0),
        );
        assert!(f.retranslate.is_none());
    }

    #[test]
    fn a_missing_translation_is_not_a_no_op() {
        // A response arrived but no translation could be read out of it — a
        // shape change, or a 200 carrying junk. That is "unavailable", not
        // "already in the target", so retrying into another language would not
        // help. (The network having died outright is the test below.)
        let f = followups(&LangConfig::default(), "idempotent", &first_pass(None, 0));
        assert!(f.retranslate.is_none());
    }

    #[test]
    fn a_first_pass_that_never_responded_plans_no_follow_ups() {
        // A dead network must cost one timeout, not two.
        let config = LangConfig::default();

        // An echo, so the responding baseline plans *both* follow-ups —
        // otherwise an arm could be suppressed by something other than the
        // guard and the test would still pass.
        let responded = first_pass(Some("idempotent"), 0);
        let baseline = followups(&config, "idempotent", &responded);
        assert!(
            baseline.definition.is_some(),
            "the baseline must exercise the definition arm"
        );
        assert!(
            baseline.retranslate.is_some(),
            "the baseline must exercise the retranslate arm"
        );

        let silent = FirstPass {
            responded: false,
            ..responded
        };
        assert_eq!(
            followups(&config, "idempotent", &silent),
            Followups::default(),
            "a first pass that never answered must plan nothing at all"
        );
    }

    // -- the no-op rule ---------------------------------------------------

    #[test]
    fn the_no_op_rule_ignores_surrounding_whitespace() {
        assert!(is_no_op("  con mèo  ", Some("con mèo")));
        assert!(is_no_op("con mèo", Some("\ncon mèo\n")));
    }

    #[test]
    fn the_no_op_rule_is_case_sensitive_and_content_sensitive() {
        assert!(!is_no_op("Haus", Some("Căn nhà")));
        assert!(!is_no_op("casa", Some("house")));
        assert!(!is_no_op("idempotent", None));
    }

    // -- resolving the final translation ----------------------------------

    #[test]
    fn resolve_prefers_a_useful_first_translation() {
        let out = resolve_translation("idempotent", Some("bình thường".into()), None);
        assert_eq!(out, Some(("bình thường".to_owned(), false)));
    }

    #[test]
    fn resolve_uses_the_retry_when_the_first_pass_was_a_no_op() {
        let out = resolve_translation("con mèo", Some("con mèo".into()), Some("the cat".into()));
        assert_eq!(out, Some(("the cat".to_owned(), true)));
    }

    #[test]
    fn resolve_reports_nothing_rather_than_echoing_the_input() {
        // Invariant 1. A proper noun is identical in every language, so the
        // retry comes back identical too — echoing it back would be the
        // "translation" that made the retry necessary in the first place.
        assert_eq!(
            resolve_translation("Google", Some("Google".into()), Some("Google".into())),
            None
        );
        // And when the retry never landed at all.
        assert_eq!(
            resolve_translation("con mèo", Some("con mèo".into()), None),
            None
        );
    }

    /// Invariant 1, over every combination the planner can produce.
    #[test]
    fn a_resolved_translation_is_never_identical_to_its_source() {
        let source = "con mèo";
        let candidates = [
            None,
            Some(source.to_owned()),
            Some("  con mèo  ".to_owned()),
            Some("the cat".to_owned()),
        ];

        for first in &candidates {
            for retry in &candidates {
                if let Some((text, _)) = resolve_translation(source, first.clone(), retry.clone()) {
                    assert_ne!(
                        text.trim(),
                        source.trim(),
                        "resolve_translation echoed its input for first={first:?} retry={retry:?}"
                    );
                }
            }
        }
    }

    /// Invariant 2, over every combination of config and first pass.
    ///
    /// Counting the requests is not enough: summing three `Option`s and
    /// asserting `<= 3` is arithmetic, true no matter what the planner does.
    /// So this inspects the requests themselves — no plan may repeat a request,
    /// and no plan may contain a translation whose answer is knowable in
    /// advance (F4: `sl == tl` returns the input verbatim).
    #[test]
    fn a_lookup_plans_at_most_three_requests_and_never_a_wasted_one() {
        let subset: Vec<Lang> = ["en", "vi", "de", "ja"].iter().map(|c| lang(c)).collect();
        let sources: Vec<Option<Lang>> = std::iter::once(None)
            .chain(subset.iter().copied().map(Some))
            .collect();
        let passes = [
            first_pass(None, 0),
            first_pass(Some("idempotent"), 0),
            first_pass(Some("bình thường"), 0),
            first_pass(Some("bình thường"), 2),
        ];

        for &source in &sources {
            for &target in &subset {
                for &other in &subset {
                    let c = LangConfig::new(source, target, other);
                    for pass in &passes {
                        let f = followups(&c, "idempotent", pass);
                        let planned: Vec<Request> = initial_request(&c, "idempotent")
                            .into_iter()
                            .chain(f.definition)
                            .chain(f.retranslate)
                            .collect();

                        assert!(
                            planned.len() <= 3,
                            "planned {} requests for {c:?}",
                            planned.len()
                        );
                        for (i, a) in planned.iter().enumerate() {
                            assert!(
                                !planned[i + 1..].contains(a),
                                "duplicate request {a:?} for {c:?}"
                            );
                            assert!(
                                a.dts != vec!["t"] || a.sl != a.tl,
                                "no-op translation request {a:?} for {c:?}"
                            );
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn a_source_equal_to_the_fallback_plans_no_retranslation() {
        // `LangConfig::new` repairs `other == target` and `source == target`,
        // but never `source == other`, so this config arrives intact. The
        // retry would be en -> en, which F4 guarantees echoes the input.
        let c = LangConfig::new(Some(Lang::EN), Lang::VI, Lang::EN);
        assert_eq!(c.sl(), "en", "the config under test must survive repair");
        assert_eq!(c.other(), Lang::EN);

        let f = followups(&c, "idempotent", &first_pass(Some("idempotent"), 0));
        assert!(f.retranslate.is_none());
    }

    #[test]
    fn a_no_op_first_pass_asks_the_target_dictionary_not_the_fallback() {
        // The endpoint handing the text back means the text is already in
        // `target`. Asking `other` would be asking the one language the
        // response just proved the text is not written in.
        let c = LangConfig::default();
        let d = followups(&c, "con mèo", &first_pass(Some("con mèo"), 0))
            .definition
            .expect("expected a definition follow-up");
        assert_eq!(d.sl, "vi");
        assert_eq!(d.tl, "vi");

        // The other branch is unchanged: a useful translation says nothing
        // about the source, so the fallback language is still the best guess.
        let d = followups(&c, "idempotent", &first_pass(Some("bình thường"), 0))
            .definition
            .expect("expected a definition follow-up");
        assert_eq!(d.sl, "en");
        assert_eq!(d.tl, "en");
    }

    /// Measured fact F2, as a structural guard: `sl=auto` mis-detects single
    /// words — `idempotent` reports `la`, `Haus` reports `en`. So the plan may
    /// branch on the configured languages and on what came *back*, never on
    /// what the endpoint claims the input was.
    #[test]
    fn what_the_endpoint_detected_never_changes_the_plan() {
        let config = LangConfig::default();
        // Two fixtures, because one leaves an arm unpinned: a useful
        // translation exercises only the definition follow-up, while a no-op
        // one — identical to the source below — exercises both. The
        // assertions on the baselines keep a future edit from quietly
        // degrading either fixture into covering nothing.
        let fixtures = [("bình thường", false), ("idempotent", true)];

        for (translation, plans_a_retranslation) in fixtures {
            let baseline = followups(&config, "idempotent", &first_pass(Some(translation), 0));
            assert!(
                baseline.definition.is_some(),
                "fixture {translation:?} must exercise the definition arm"
            );
            assert_eq!(
                baseline.retranslate.is_some(),
                plans_a_retranslation,
                "fixture {translation:?} must exercise the retranslate arm as declared"
            );

            for detected in [None, Some(Lang::EN), Some(Lang::VI), Some(lang("la"))] {
                let pass = FirstPass {
                    detected,
                    ..first_pass(Some(translation), 0)
                };
                assert_eq!(
                    followups(&config, "idempotent", &pass),
                    baseline,
                    "detection changed the plan for {translation:?}: {detected:?}"
                );
            }
        }
    }

    /// Invariant 4, the latency claim: an explicit source and a useful
    /// translation cost exactly one request.
    #[test]
    fn an_explicit_source_with_a_useful_answer_costs_exactly_one_request() {
        let c = LangConfig::new(Some(lang("de")), Lang::VI, Lang::EN);
        let pass = first_pass(Some("Căn nhà"), 1);
        assert!(initial_request(&c, "Haus").is_some());
        let f = followups(&c, "Haus", &pass);
        assert!(f.definition.is_none());
        assert!(f.retranslate.is_none());
    }
}
