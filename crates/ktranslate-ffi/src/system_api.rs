use crate::json_out;
use crate::state::cstr_to_string;
use ktranslate_core::{capture, tts};
use std::os::raw::c_char;

/// Cổng quyền *poll* hàm này thay vì hỏi một lần, để một lần cấp quyền trong
/// System Settings có hiệu lực mà không phải khởi động lại app.
#[no_mangle]
pub extern "C" fn kt_check_accessibility() -> bool {
    std::panic::catch_unwind(capture::has_accessibility_permission).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn kt_request_accessibility() -> bool {
    std::panic::catch_unwind(capture::request_accessibility_permission).unwrap_or(false)
}

/// UI gate nút loa theo hàm này thay vì giả định — một nút im lặng không làm
/// gì còn tệ hơn không có nút.
#[no_mangle]
pub extern "C" fn kt_tts_available() -> bool {
    std::panic::catch_unwind(tts::is_available).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn kt_speak(text: *const c_char) -> *mut c_char {
    json_out(move || {
        let text = cstr_to_string(text);
        serde_json::json!({ "ok": tts::speak(&text).is_ok() })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn system_checks_never_panic() {
        // Giá trị phụ thuộc máy chạy test, nên chỉ khẳng định được điều thật
        // sự quan trọng: chúng trả về thay vì nổ qua ranh giới C.
        let _ = kt_check_accessibility();
        let _ = kt_tts_available();
    }

    #[test]
    fn speak_of_empty_text_returns_the_agreed_shape() {
        let empty = std::ffi::CString::new("").unwrap();
        let ptr = kt_speak(empty.as_ptr());
        let s = unsafe { std::ffi::CStr::from_ptr(ptr) }.to_str().unwrap().to_owned();
        crate::kt_string_free(ptr);
        let v: serde_json::Value = serde_json::from_str(&s).unwrap();
        assert!(v.get("ok").and_then(|b| b.as_bool()).is_some());
    }
}
