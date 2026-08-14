use crate::json_out;
use crate::state::{self, cstr_to_string};
use ktranslate_core::capture;
use ktranslate_core::provider::GtxProvider;
use std::os::raw::c_char;

/// Bắt lựa chọn hiện tại. **Swift phải gọi TRƯỚC khi show popup** — show trước
/// sẽ cướp keyboard focus, ⌘C giả lập đi vào window của chính mình và mọi lần
/// capture trả về rỗng. Bug về thứ tự, trông y hệt bug về quyền.
#[no_mangle]
pub extern "C" fn kt_capture() -> *mut c_char {
    json_out(|| match capture::capture_selection() {
        Ok(text) => serde_json::json!({ "ok": true, "text": text }),
        Err(e) => serde_json::json!({ "ok": false, "text": "", "error": e.to_string() }),
    })
}

/// Tra `text`. Đồng bộ và có HTTP bên trong — **Swift phải gọi trên background
/// queue**, gọi trên main thread sẽ đóng băng đúng cái popup đang hiện.
#[no_mangle]
pub extern "C" fn kt_lookup(text: *const c_char) -> *mut c_char {
    let text = cstr_to_string(text);
    json_out(move || {
        let config = state::with_store(|s| s.lang_config().unwrap_or_default()).unwrap_or_default();
        let lookup = GtxProvider::new().lookup(&text, &config);
        // Lịch sử là tiện ích, không phải một phần của câu trả lời. Ghi hỏng
        // không được làm mất kết quả người dùng đang chờ.
        state::with_store(|s| {
            let _ = s.record_lookup(&lookup);
        });
        serde_json::to_value(&lookup).unwrap_or(serde_json::Value::Null)
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
    fn capture_always_returns_the_agreed_shape() {
        // Trên máy không có Accessibility đây là đường thất bại — vẫn phải
        // đúng shape, không được null hay JSON rỗng.
        let v = take(kt_capture());
        assert!(v.get("ok").and_then(|b| b.as_bool()).is_some());
        assert!(v.get("text").and_then(|t| t.as_str()).is_some());
    }

    #[test]
    fn lookup_of_empty_text_returns_a_lookup_not_an_error() {
        // Hợp đồng provider: mọi thất bại thành trạng thái "unavailable".
        // UI không có đường xử lý lỗi, nên FFI không được tạo ra một.
        let empty = CString::new("").unwrap();
        let v = take(kt_lookup(empty.as_ptr()));
        assert!(v.get("source").is_some(), "expected a Lookup, got {v}");
        assert!(v.get("target_lang").is_some());
    }

    #[test]
    fn lookup_survives_a_null_pointer() {
        let v = take(kt_lookup(std::ptr::null()));
        assert!(v.get("source").is_some());
    }
}
