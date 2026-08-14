use crate::json_out;
use crate::state::{self, cstr_to_string};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn kt_save_word(word: *const c_char) -> *mut c_char {
    let word = cstr_to_string(word);
    json_out(move || {
        let ok = state::with_store(|s| s.save_word(&word).is_ok()).unwrap_or(false);
        serde_json::json!({ "ok": ok })
    })
}

#[no_mangle]
pub extern "C" fn kt_unsave_word(word: *const c_char) -> *mut c_char {
    let word = cstr_to_string(word);
    json_out(move || {
        let ok = state::with_store(|s| s.unsave_word(&word).is_ok()).unwrap_or(false);
        serde_json::json!({ "ok": ok })
    })
}

#[no_mangle]
pub extern "C" fn kt_is_saved(word: *const c_char) -> *mut c_char {
    let word = cstr_to_string(word);
    json_out(move || {
        let saved = state::with_store(|s| s.is_saved(&word).unwrap_or(false)).unwrap_or(false);
        serde_json::json!({ "saved": saved })
    })
}

#[no_mangle]
pub extern "C" fn kt_saved_words() -> *mut c_char {
    json_out(|| {
        let words = state::with_store(|s| s.saved_words().unwrap_or_default()).unwrap_or_default();
        serde_json::to_value(words).unwrap_or_else(|_| serde_json::json!([]))
    })
}

#[no_mangle]
pub extern "C" fn kt_recent_lookups(limit: u32) -> *mut c_char {
    json_out(move || {
        let rows =
            state::with_store(|s| s.recent(limit as usize).unwrap_or_default()).unwrap_or_default();
        serde_json::to_value(rows).unwrap_or_else(|_| serde_json::json!([]))
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
    fn save_then_query_then_unsave() {
        let _guard = state::TEST_GUARD.lock().unwrap_or_else(|p| p.into_inner());
        state::reset_for_test();
        let dir = tempfile::tempdir().unwrap();
        let db = CString::new(dir.path().join("s.db").to_str().unwrap()).unwrap();
        assert!(crate::kt_init(db.as_ptr()));

        let word = CString::new("ephemeral").unwrap();
        assert_eq!(take(kt_save_word(word.as_ptr())).get("ok").and_then(|b| b.as_bool()), Some(true));
        assert_eq!(take(kt_is_saved(word.as_ptr())).get("saved").and_then(|b| b.as_bool()), Some(true));

        let list = take(kt_saved_words());
        assert!(list
            .as_array()
            .unwrap()
            .iter()
            .any(|e| e.get("word").and_then(|w| w.as_str()) == Some("ephemeral")));

        assert_eq!(take(kt_unsave_word(word.as_ptr())).get("ok").and_then(|b| b.as_bool()), Some(true));
        assert_eq!(take(kt_is_saved(word.as_ptr())).get("saved").and_then(|b| b.as_bool()), Some(false));
    }

    #[test]
    fn recent_lookups_returns_an_array_shape() {
        // Db hỏng không được làm app chết — mảng rỗng, không phải null.
        let v = take(kt_recent_lookups(10));
        assert!(v.is_array(), "expected an array, got {v}");
    }
}
