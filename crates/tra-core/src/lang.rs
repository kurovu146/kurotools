//! Language codes, as the gtx endpoint spells them.
//!
//! A newtype over a `&'static str` borrowed from [`SUPPORTED`], so a `Lang`
//! cannot exist for a code the endpoint does not know. That matters because
//! these values are interpolated straight into a URL: validating once at
//! construction means no caller has to remember to sanitise.
//!
//! Display names are deliberately absent. The frontend derives them with
//! `Intl.DisplayNames`, which is already localised and already correct — a
//! hand-maintained table of 130 endonyms here would be 130 chances to be
//! wrong and would need translating itself.

use serde::{Deserialize, Serialize};

/// Every language the free gtx endpoint accepts.
///
/// Spelt as Google spells them, legacy codes included: `iw` not `he`, `jw`
/// not `jv`. Those are what the endpoint answers to; the frontend maps them
/// to modern codes for display only.
pub const SUPPORTED: &[&str] = &[
    "af", "ak", "am", "ar", "as", "ay", "az", "be", "bg", "bho", "bm", "bn", "bs", "ca", "ceb",
    "ckb", "co", "cs", "cy", "da", "de", "doi", "dv", "ee", "el", "en", "eo", "es", "et", "eu",
    "fa", "fi", "fil", "fr", "fy", "ga", "gd", "gl", "gn", "gom", "gu", "ha", "haw", "hi", "hmn",
    "hr", "ht", "hu", "hy", "id", "ig", "ilo", "is", "it", "iw", "ja", "jw", "ka", "kk", "km",
    "kn", "ko", "kri", "ku", "ky", "la", "lb", "lg", "ln", "lo", "lt", "lus", "lv", "mai", "mg",
    "mi", "mk", "ml", "mn", "mni-Mtei", "mr", "ms", "mt", "my", "ne", "nl", "no", "nso", "ny",
    "om", "or", "pa", "pl", "ps", "pt", "qu", "ro", "ru", "rw", "sa", "sd", "si", "sk", "sl", "sm",
    "sn", "so", "sq", "sr", "st", "su", "sv", "sw", "ta", "te", "tg", "th", "ti", "tk", "tr", "ts",
    "tt", "ug", "uk", "ur", "uz", "vi", "xh", "yi", "yo", "zh-CN", "zh-TW", "zu",
];

/// A validated language code.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Lang(&'static str);

impl Lang {
    /// English — the default fallback language.
    pub const EN: Lang = Lang("en");
    /// Vietnamese — the default target.
    pub const VI: Lang = Lang("vi");

    /// The code, ready to interpolate into a request.
    pub fn code(self) -> &'static str {
        self.0
    }

    /// Look a code up. `None` for anything not in [`SUPPORTED`], including
    /// `"auto"` — the absence of a source language is `Option::None`, not a
    /// language whose name happens to be "auto".
    pub fn from_code(code: &str) -> Option<Lang> {
        SUPPORTED
            .iter()
            .find(|known| **known == code)
            .map(|known| Lang(known))
    }
}

/// Every supported language, in the order [`SUPPORTED`] declares them.
pub fn all() -> impl Iterator<Item = Lang> {
    SUPPORTED.iter().map(|code| Lang(code))
}

impl Serialize for Lang {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.0)
    }
}

impl<'de> Deserialize<'de> for Lang {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let code = String::deserialize(deserializer)?;
        Lang::from_code(&code)
            .ok_or_else(|| serde::de::Error::custom(format!("unknown language code: {code}")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_known_code_round_trips() {
        assert_eq!(Lang::from_code("de").map(Lang::code), Some("de"));
        assert_eq!(Lang::from_code("zh-CN").map(Lang::code), Some("zh-CN"));
    }

    #[test]
    fn an_unknown_code_is_rejected() {
        // Guards against a stored setting or an IPC payload smuggling an
        // arbitrary string into a URL.
        assert_eq!(Lang::from_code("klingon"), None);
        assert_eq!(Lang::from_code(""), None);
        assert_eq!(
            Lang::from_code("auto"),
            None,
            "`auto` is the absence of a source, not a language"
        );
    }

    #[test]
    fn codes_are_unique() {
        let mut seen: Vec<&str> = SUPPORTED.to_vec();
        seen.sort_unstable();
        let before = seen.len();
        seen.dedup();
        assert_eq!(seen.len(), before, "duplicate language code in SUPPORTED");
    }

    #[test]
    fn the_table_holds_every_language_the_defaults_and_the_dictionary_need() {
        // The seven with measured dictionary support (spec F3) plus the two
        // defaults. If a refactor drops one of these the definition pane
        // silently loses a language.
        for code in ["en", "es", "fr", "de", "it", "ru", "ar", "vi"] {
            assert!(
                Lang::from_code(code).is_some(),
                "{code} missing from SUPPORTED"
            );
        }
    }

    #[test]
    fn the_named_constants_match_their_codes() {
        assert_eq!(Lang::EN.code(), "en");
        assert_eq!(Lang::VI.code(), "vi");
    }

    #[test]
    fn all_yields_every_code_once() {
        assert_eq!(all().count(), SUPPORTED.len());
    }

    #[test]
    fn a_lang_serialises_as_a_bare_code() {
        assert_eq!(serde_json::to_string(&Lang::EN).unwrap(), "\"en\"");
        assert_eq!(
            serde_json::from_str::<Lang>("\"de\"").unwrap(),
            Lang::from_code("de").unwrap()
        );
        assert!(serde_json::from_str::<Lang>("\"nope\"").is_err());
    }
}
