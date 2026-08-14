use crate::json_out;
use crate::state::{self, cstr_to_string};
use ktranslate_core::config::LangConfig;
use ktranslate_core::lang::{self, Lang};
use ktranslate_core::store::StoreError;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn kt_languages() -> *mut c_char {
    json_out(|| serde_json::json!(lang::SUPPORTED))
}

#[no_mangle]
pub extern "C" fn kt_lang_config() -> *mut c_char {
    json_out(|| {
        let config = state::with_store(|s| s.lang_config().unwrap_or_default()).unwrap_or_default();
        serde_json::to_value(config).unwrap_or(serde_json::Value::Null)
    })
}

/// `source` rỗng hoặc `"auto"` đều nghĩa là không có ngôn ngữ nguồn.
#[no_mangle]
pub extern "C" fn kt_set_lang_config(
    source: *const c_char,
    target: *const c_char,
    other: *const c_char,
) -> *mut c_char {
    json_out(move || {
        let (source, target, other) = (
            cstr_to_string(source),
            cstr_to_string(target),
            cstr_to_string(other),
        );
        let source_lang = match source.as_str() {
            "" | "auto" => None,
            code => match Lang::from_code(code) {
                Some(l) => Some(l),
                None => return serde_json::json!({ "error": format!("unknown language: {code}") }),
            },
        };
        let (Some(target_lang), Some(other_lang)) =
            (Lang::from_code(&target), Lang::from_code(&other))
        else {
            return serde_json::json!({ "error": "unknown language" });
        };

        let config = LangConfig::new(source_lang, target_lang, other_lang);
        // `set_lang_config`'s failure must surface — silently swallowing it
        // (as this used to) would let the UI believe a write succeeded when
        // nothing was actually persisted. `push_recent_lang` stays
        // best-effort, matching the Tauri command this replaces. `with_store`
        // returning `None` (store never initialized) is a write that never
        // happened at all, and must be reported the same way as one that
        // happened and failed — not silently treated as success by falling
        // through the `Err` check below.
        let write: Option<Result<(), StoreError>> = state::with_store(|s| {
            s.set_lang_config(&config)?;
            if let Some(src) = config.source() {
                let _ = s.push_recent_lang(src);
            }
            let _ = s.push_recent_lang(config.target());
            Ok(())
        });
        match write {
            Some(Ok(())) => serde_json::to_value(config).unwrap_or(serde_json::Value::Null),
            Some(Err(e)) => serde_json::json!({ "error": e.to_string() }),
            None => serde_json::json!({ "error": "store not initialized" }),
        }
    })
}

#[no_mangle]
pub extern "C" fn kt_recent_languages() -> *mut c_char {
    json_out(|| {
        let langs = state::with_store(|s| s.recent_langs().unwrap_or_default()).unwrap_or_default();
        serde_json::to_value(langs).unwrap_or_else(|_| serde_json::json!([]))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::{CStr, CString};

    fn take(ptr: *mut std::os::raw::c_char) -> serde_json::Value {
        let s = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_owned();
        crate::kt_string_free(ptr);
        serde_json::from_str(&s).expect("FFI must always return valid JSON")
    }

    #[test]
    fn languages_lists_codes_as_plain_strings() {
        let v = take(kt_languages());
        let arr = v.as_array().expect("expected an array");
        assert!(arr.iter().any(|x| x == "en"));
        assert!(arr.iter().any(|x| x == "vi"));
    }

    #[test]
    fn set_lang_config_returns_what_was_actually_stored() {
        // LangConfig::new tự sửa xung đột, nên giá trị trả về có thể khác giá
        // trị yêu cầu. UI phải render câu trả lời, không phải phỏng đoán lạc
        // quan của chính nó.
        let _guard = state::TEST_GUARD.lock().unwrap_or_else(|p| p.into_inner());
        state::reset_for_test();
        let dir = tempfile::tempdir().unwrap();
        let db = CString::new(dir.path().join("l.db").to_str().unwrap()).unwrap();
        crate::kt_init(db.as_ptr());

        let de = CString::new("de").unwrap();
        let vi = CString::new("vi").unwrap();
        let en = CString::new("en").unwrap();
        let v = take(kt_set_lang_config(de.as_ptr(), vi.as_ptr(), en.as_ptr()));
        assert_eq!(v.get("target").and_then(|x| x.as_str()), Some("vi"));
    }

    #[test]
    fn set_lang_config_rejects_an_unknown_code() {
        let bad = CString::new("zzz").unwrap();
        let vi = CString::new("vi").unwrap();
        let en = CString::new("en").unwrap();
        let v = take(kt_set_lang_config(bad.as_ptr(), vi.as_ptr(), en.as_ptr()));
        assert!(v.get("error").is_some(), "expected an error payload, got {v}");
    }

    #[test]
    fn auto_and_empty_both_mean_no_source_language() {
        let _guard = state::TEST_GUARD.lock().unwrap_or_else(|p| p.into_inner());
        state::reset_for_test();
        let dir = tempfile::tempdir().unwrap();
        let db = CString::new(dir.path().join("a.db").to_str().unwrap()).unwrap();
        crate::kt_init(db.as_ptr());

        let vi = CString::new("vi").unwrap();
        let en = CString::new("en").unwrap();
        for s in ["auto", ""] {
            let src = CString::new(s).unwrap();
            let v = take(kt_set_lang_config(src.as_ptr(), vi.as_ptr(), en.as_ptr()));
            assert!(
                v.get("source").map(|x| x.is_null()).unwrap_or(false),
                "source {s:?} should store as null, got {v}"
            );
        }
    }

    #[test]
    fn a_failed_write_is_reported_not_swallowed() {
        // Delete the store's backing directory out from under the open
        // connection: SQLite can still read through the existing file
        // handle, but any write needs to create a rollback journal in that
        // directory first and fails with "attempt to write a readonly
        // database". Cheapest reliable way to force set_lang_config to fail
        // without depending on OS permission semantics (which root ignores).
        let _guard = state::TEST_GUARD.lock().unwrap_or_else(|p| p.into_inner());
        state::reset_for_test();
        let dir = tempfile::tempdir().unwrap();
        let db = CString::new(dir.path().join("w.db").to_str().unwrap()).unwrap();
        crate::kt_init(db.as_ptr());
        drop(dir);

        let de = CString::new("de").unwrap();
        let vi = CString::new("vi").unwrap();
        let en = CString::new("en").unwrap();
        let v = take(kt_set_lang_config(de.as_ptr(), vi.as_ptr(), en.as_ptr()));
        assert!(
            v.get("error").is_some(),
            "a failed write must surface as an error, got {v}"
        );
    }

    #[test]
    fn a_missing_store_is_reported_as_an_error_not_success() {
        // kt_init was never called for this store, so with_store returns None
        // outright — a distinct case from set_lang_config's own Err, and one
        // the earlier fix missed: `write` being None fell through the `if let
        // Some(Err(e))` check and reached the success path unchallenged.
        let _guard = state::TEST_GUARD.lock().unwrap_or_else(|p| p.into_inner());
        state::reset_for_test();

        let de = CString::new("de").unwrap();
        let vi = CString::new("vi").unwrap();
        let en = CString::new("en").unwrap();
        let v = take(kt_set_lang_config(de.as_ptr(), vi.as_ptr(), en.as_ptr()));
        assert!(
            v.get("error").is_some(),
            "a write with no store must surface as an error, got {v}"
        );
    }
}
