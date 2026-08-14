//! Which languages a lookup runs in.

use serde::{Deserialize, Serialize};

use crate::lang::Lang;

/// The three languages a lookup needs.
///
/// `other` does double duty: it is the target when the text turns out to
/// already be in `target`, and it is the definition language when `source` is
/// auto. Both defaults are English and for any real user they name the same
/// thing — "the other language I deal with" — so splitting them would buy a
/// case that could not be named.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct LangConfig {
    source: Option<Lang>,
    target: Lang,
    other: Lang,
}

impl Default for LangConfig {
    fn default() -> Self {
        Self {
            source: None,
            target: Lang::VI,
            other: Lang::EN,
        }
    }
}

impl LangConfig {
    /// Build a config, repairing collisions rather than rejecting them.
    ///
    /// Total by design. A language picker that refuses a selection is worse
    /// than one that adjusts around it, and a total constructor is what lets
    /// the two invariants be proven exhaustively instead of sampled.
    ///
    /// The three repairs below have to run in this order. If the target swap
    /// ran first, a triple collision (`source == target == other`, which the
    /// picker reaches whenever someone selects the same language everywhere)
    /// would swap `target` for a same-valued `other` and stay collided with
    /// `source` — the "fallback" the swap reaches for has to already be safe.
    pub fn new(source: Option<Lang>, target: Lang, other: Lang) -> Self {
        // `other` is the escape hatch *from* `target`; if it starts out equal
        // to `target` it cannot serve that role. Fix this against the
        // as-given target before anything below is allowed to move it.
        let other = if other == target {
            default_other(target)
        } else {
            other
        };

        // Picking a source equal to the target asks for a no-op pair. The
        // newest choice — the source — wins, and the destination moves to the
        // fallback, which by the line above is already guaranteed safe.
        let target = match source {
            Some(s) if s == target => other,
            _ => target,
        };

        // The swap above can set `target` to `other`'s value, recreating the
        // exact collision the first repair just cleared. Clear it again.
        let other = if other == target {
            default_other(target)
        } else {
            other
        };

        Self {
            source,
            target,
            other,
        }
    }

    pub fn source(&self) -> Option<Lang> {
        self.source
    }

    pub fn target(&self) -> Lang {
        self.target
    }

    pub fn other(&self) -> Lang {
        self.other
    }

    /// The `sl` query parameter: an explicit code, or `auto`.
    pub fn sl(&self) -> &'static str {
        match self.source {
            Some(l) => l.code(),
            None => "auto",
        }
    }
}

/// The fallback language to use when the configured one collided.
///
/// English, unless the target *is* English. Deliberately limited to the app's
/// two defaults: a repair that reached for some third language would
/// translate into something the user never chose.
fn default_other(target: Lang) -> Lang {
    if target == Lang::EN {
        Lang::VI
    } else {
        Lang::EN
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lang(code: &str) -> Lang {
        Lang::from_code(code).expect("test uses a supported code")
    }

    #[test]
    fn the_default_is_auto_to_vietnamese_falling_back_to_english() {
        let c = LangConfig::default();
        assert_eq!(c.source(), None);
        assert_eq!(c.target(), Lang::VI);
        assert_eq!(c.other(), Lang::EN);
        assert_eq!(c.sl(), "auto");
    }

    #[test]
    fn an_explicit_source_is_kept_verbatim() {
        let c = LangConfig::new(Some(lang("de")), Lang::VI, Lang::EN);
        assert_eq!(c.source(), Some(lang("de")));
        assert_eq!(c.sl(), "de");
    }

    #[test]
    fn a_source_equal_to_the_target_pushes_the_target_to_the_fallback() {
        // The user picked Vietnamese as the source while translating into
        // Vietnamese. Their newest choice wins; the destination moves.
        let c = LangConfig::new(Some(Lang::VI), Lang::VI, Lang::EN);
        assert_eq!(c.source(), Some(Lang::VI));
        assert_eq!(c.target(), Lang::EN);
        assert_ne!(
            c.other(),
            c.target(),
            "the repair must not leave `other` on the target"
        );
    }

    #[test]
    fn a_fallback_equal_to_the_target_is_moved_off_it() {
        let c = LangConfig::new(None, Lang::EN, Lang::EN);
        assert_eq!(c.target(), Lang::EN);
        assert_ne!(c.other(), Lang::EN);
    }

    #[test]
    fn the_repair_never_invents_a_language_outside_the_two_defaults() {
        // A repair that reached for a third language would silently translate
        // into something the user never chose.
        let c = LangConfig::new(None, Lang::EN, Lang::EN);
        assert_eq!(c.other(), Lang::VI);
        let c = LangConfig::new(None, lang("de"), lang("de"));
        assert_eq!(c.other(), Lang::EN);
    }

    /// The invariants, proven over every combination of a representative
    /// subset rather than a handful of examples. 9 sources x 8 targets x 8
    /// fallbacks = 576 configs, which is exhaustive at a tractable size.
    #[test]
    fn the_invariants_hold_for_every_combination() {
        let subset: Vec<Lang> = ["en", "vi", "de", "ja", "zh-CN", "es", "fr", "ar"]
            .iter()
            .map(|c| lang(c))
            .collect();

        let sources: Vec<Option<Lang>> = std::iter::once(None)
            .chain(subset.iter().copied().map(Some))
            .collect();

        for &source in &sources {
            for &target in &subset {
                for &other in &subset {
                    let c = LangConfig::new(source, target, other);
                    assert_ne!(
                        c.other(),
                        c.target(),
                        "other == target for new({source:?}, {target:?}, {other:?})"
                    );
                    assert_ne!(
                        c.source(),
                        Some(c.target()),
                        "source == target for new({source:?}, {target:?}, {other:?})"
                    );
                }
            }
        }
    }

    #[test]
    fn the_invariants_hold_for_every_supported_target() {
        // The subset above cannot catch a repair rule that misbehaves for one
        // specific language, so sweep the whole table on the axis that the
        // repair actually branches on.
        for target in crate::lang::all() {
            let c = LangConfig::new(Some(target), target, target);
            assert_ne!(c.other(), c.target());
            assert_ne!(c.source(), Some(c.target()));
        }
    }
}
