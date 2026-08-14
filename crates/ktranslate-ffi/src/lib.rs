//! Bề mặt C ABI của KuroTools. Mọi thứ đi qua đây đều là JSON: `Lookup` là một
//! cây lồng nhau, và bridge struct C thủ công tốn gấp nhiều lần mà không được
//! gì — mỗi lần tra vốn đã kèm một round-trip HTTP.
#![allow(clippy::missing_safety_doc)]

mod lookup_api;
mod state;

use std::ffi::CString;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;

/// Mọi entry point FFI đi qua đây. Panic vượt ranh giới C là undefined
/// behaviour, nên `catch_unwind` không phải tuỳ chọn.
fn json_out(f: impl FnOnce() -> serde_json::Value) -> *mut c_char {
    let value = catch_unwind(AssertUnwindSafe(f))
        .unwrap_or_else(|_| serde_json::json!({ "error": "panic" }));
    let text = serde_json::to_string(&value)
        .unwrap_or_else(|_| r#"{"error":"serialize_failed"}"#.to_string());
    match CString::new(text) {
        Ok(s) => s.into_raw(),
        Err(_) => CString::new(r#"{"error":"nul_byte"}"#).expect("literal").into_raw(),
    }
}

/// Swift PHẢI gọi hàm này cho mọi con trỏ nhận về, kể cả trên đường lỗi.
#[no_mangle]
pub extern "C" fn kt_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe { drop(CString::from_raw(ptr)) };
}

#[no_mangle]
pub extern "C" fn kt_init(db_path: *const c_char) -> bool {
    let path = state::cstr_to_string(db_path);
    catch_unwind(AssertUnwindSafe(|| state::init(Path::new(&path)))).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn free_tolerates_null() {
        // Swift gọi free trên đường lỗi, nơi con trỏ có thể là null.
        kt_string_free(std::ptr::null_mut());
    }

    #[test]
    fn json_out_round_trips() {
        let ptr = json_out(|| serde_json::json!({"hello": "world"}));
        assert!(!ptr.is_null());
        let s = unsafe { std::ffi::CStr::from_ptr(ptr) }.to_str().unwrap().to_owned();
        kt_string_free(ptr);
        assert_eq!(s, r#"{"hello":"world"}"#);
    }

    #[test]
    fn json_out_survives_a_panic() {
        // Panic vượt ranh giới C là undefined behaviour. Phải thành JSON lỗi.
        let ptr = json_out(|| panic!("boom"));
        let s = unsafe { std::ffi::CStr::from_ptr(ptr) }.to_str().unwrap().to_owned();
        kt_string_free(ptr);
        assert!(s.contains("panic"), "expected an error payload, got {s}");
    }

    #[test]
    fn init_opens_a_store_and_is_idempotent() {
        let dir = tempfile::tempdir().unwrap();
        let c = CString::new(dir.path().join("t.db").to_str().unwrap()).unwrap();
        assert!(kt_init(c.as_ptr()));
        assert!(kt_init(c.as_ptr()), "second init must not fail");
        assert!(state::with_store(|s| s.recent(1).is_ok()).unwrap_or(false));
    }
}
