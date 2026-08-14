use ktranslate_core::store::Store;
use std::ffi::CStr;
use std::os::raw::c_char;
use std::path::Path;
use std::sync::{Mutex, OnceLock};

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();

/// Mở store một lần. Gọi lại là no-op thành công — Swift gọi từ
/// `applicationDidFinishLaunching`, và một lần gọi lại không được là lỗi cứng.
pub(crate) fn init(path: &Path) -> bool {
    if STORE.get().is_some() {
        return true;
    }
    match Store::open(path) {
        Ok(store) => STORE.set(Mutex::new(store)).is_ok(),
        Err(_) => false,
    }
}

/// `None` khi `kt_init` chưa gọi hoặc đã thất bại. Mọi hàm lưu trữ phải xử lý
/// được — app vẫn phải tra cứu được khi db hỏng.
pub(crate) fn with_store<T>(f: impl FnOnce(&Store) -> T) -> Option<T> {
    let lock = STORE.get()?;
    // Mutex poisoned nghĩa là một panic trước đó, không phải store hỏng.
    let guard = lock.lock().unwrap_or_else(|p| p.into_inner());
    Some(f(&guard))
}

pub(crate) fn cstr_to_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned()
}
