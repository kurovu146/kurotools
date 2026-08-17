use ktranslate_core::store::Store;
use std::ffi::CStr;
use std::os::raw::c_char;
use std::path::Path;
use std::sync::Mutex;

/// A plain `Mutex<Option<Store>>` rather than `OnceLock<Mutex<Store>>`: the
/// `OnceLock` version could only ever honour the *first* `path` any caller
/// passed in, silently ignoring every later one — harmless in production
/// (`kt_init` really is called once), but it meant every test that opened its
/// own throwaway database was actually operating on whichever other test's
/// database won the race to go first, including after that test's own
/// `tempfile::tempdir()` had already deleted it out from under the open
/// connection. `reset_for_test` below is what a test uses to get its own copy.
static STORE: Mutex<Option<Store>> = Mutex::new(None);

/// Mở store một lần. Gọi lại là no-op thành công — Swift gọi từ
/// `applicationDidFinishLaunching`, và một lần gọi lại không được là lỗi cứng.
pub(crate) fn init(path: &Path) -> bool {
    // Mutex poisoned nghĩa là một panic trước đó, không phải store hỏng.
    let mut guard = STORE.lock().unwrap_or_else(|p| p.into_inner());
    if guard.is_some() {
        return true;
    }
    match Store::open(path) {
        Ok(store) => {
            *guard = Some(store);
            true
        }
        Err(_) => false,
    }
}

/// Đóng store đang mở. Trả `true` cả khi chưa có store nào — Swift gọi hàm
/// này trên đường dọn dẹp, và "không có gì để đóng" không phải lỗi.
///
/// Đây là lý do `STORE` là `Mutex<Option<Store>>` chứ không phải
/// `OnceLock`: đổi chỗ db cần đóng rồi mở lại một đường dẫn KHÁC.
pub(crate) fn close() -> bool {
    let mut guard = STORE.lock().unwrap_or_else(|p| p.into_inner());
    *guard = None;
    true
}

/// `None` khi `kt_init` chưa gọi hoặc đã thất bại. Mọi hàm lưu trữ phải xử lý
/// được — app vẫn phải tra cứu được khi db hỏng.
pub(crate) fn with_store<T>(f: impl FnOnce(&Store) -> T) -> Option<T> {
    let guard = STORE.lock().unwrap_or_else(|p| p.into_inner());
    guard.as_ref().map(f)
}

pub(crate) fn cstr_to_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned()
}

/// Đóng store hiện tại (nếu có), để test sau gọi `kt_init` với `tempfile::tempdir()`
/// của CHÍNH NÓ thay vì kế thừa store — và thư mục đã bị Drop — của một test khác.
/// Chỉ tồn tại dưới test; production luôn gọi `kt_init` đúng một lần.
#[cfg(test)]
pub(crate) fn reset_for_test() {
    let mut guard = STORE.lock().unwrap_or_else(|p| p.into_inner());
    *guard = None;
}

/// Mọi test đụng `kt_init`/`reset_for_test` phải giữ guard này suốt hàm test.
/// `STORE` dùng chung cho cả binary test, nên hai test cùng gọi `kt_init` song
/// song mà không giữ guard này có thể thấy nhau reset giữa chừng — guard tuần
/// tự hoá đúng những test cần, không phải buộc `--test-threads=1` cho cả suite.
#[cfg(test)]
pub(crate) static TEST_GUARD: Mutex<()> = Mutex::new(());
