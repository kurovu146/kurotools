import AppKit
import Carbon.HIToolbox

/// Global hotkey qua Carbon's `RegisterEventHotKey` — API DUY NHẤT trên macOS
/// đăng ký được một tổ hợp phím hoạt động bất kể app nào đang active, kể cả
/// khi app này không có cửa sổ nào hiện. Đối chiếu
/// `~/Dev/ktranslate/src-tauri/src/hotkey.rs` (cùng bất biến, bọc Carbon qua
/// `tauri-plugin-global-shortcut` ở Rust).
///
/// 🔑 BẤT BIẾN 1 (task-18-brief.md): `RegisterEventHotKey` KHÔNG cần quyền
/// Accessibility. Quyền đó chỉ chặn việc *theo dõi*/đọc phím của app khác
/// (`CGEventTap`, `NSEvent.addGlobalMonitorForEvents`) — Carbon hotkey đăng
/// ký một tổ hợp phím với Window Server ở một tầng khác hẳn, không đụng
/// stream sự kiện của app khác. Vì vậy hotkey chạy được ngay lần khởi động
/// đầu tiên dù Accessibility bị từ chối; chỉ bước ĐỌC LỰA CHỌN sau đó
/// (`KTranslateBridge.capture`) mới bị chặn quyền — và khi đó popup vẫn hiện,
/// chỉ hiện cổng xin quyền (`.needsPermission`) thay vì im lặng như không có
/// gì xảy ra. Đó là lý do một app bị từ chối quyền vẫn để lại một app dùng
/// được, không phải một app chết.
public final class HotkeyMonitor {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let handler: () -> Void
    private let hotKeyID: EventHotKeyID

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// Chữ ký 4 ký tự Carbon dùng để phân biệt hotkey của app này với hotkey
    /// app khác cùng đăng ký qua cùng API trên cùng máy — không mang ý nghĩa
    /// gì khác ngoài một giá trị khó trùng.
    private static let signature: OSType = fourCharCode("KuTr")

    public init(
        keyCode: UInt32 = UInt32(kVK_ANSI_D), modifiers: UInt32 = UInt32(cmdKey | shiftKey),
        handler: @escaping () -> Void
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
        self.hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
    }

    /// Đăng ký hotkey với hệ thống. Gọi lần hai khi đã đăng ký là no-op an
    /// toàn (trả `true` ngay, không cài thêm một event handler thứ hai).
    ///
    /// `false` gần như luôn nghĩa là app khác đã chiếm tổ hợp phím này — đối
    /// chiếu `hotkey.rs::init`, đây KHÔNG phải lỗi đáng dừng app: log rồi để
    /// app tiếp tục chạy, người dùng vẫn dùng được qua đường khác cho tới khi
    /// đổi tổ hợp phím trong Settings.
    @discardableResult
    public func register() -> Bool {
        guard hotKeyRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Closure literal KHÔNG được capture bất kỳ biến cục bộ nào của
        // `register()` — chỉ có vậy Swift mới chuyển nó thành một con trỏ
        // hàm C (`EventHandlerUPP`) được. Danh tính instance đi vòng qua
        // `selfPtr`/`userData`, không qua capture.
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
                var firedID = EventHotKeyID()
                GetEventParameter(
                    eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &firedID)
                guard firedID.signature == HotkeyMonitor.signature else { return OSStatus(eventNotHandledErr) }

                // Carbon bơm sự kiện hotkey qua CÙNG main run loop với Cocoa
                // trong một app bình thường — không phải thread riêng (cùng
                // cơ sở `PermissionGateModel.startPolling` đã dựa vào cho
                // `Timer` + `RunLoop.main`). Trampoline này tự nó
                // `nonisolated` (không thể gắn `@MainActor` lên một
                // `@convention(c)` function), nên gọi vào `handler`
                // (MainActor-isolated vì được tạo trong ngữ cảnh MainActor
                // của `TranslateController`) phải qua `assumeIsolated` —
                // trình biên dịch không tự suy luận được qua ranh giới C này.
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { monitor.handler() }
                return noErr
            },
            1, &eventType, selfPtr, &eventHandler)

        guard installStatus == noErr else { return false }

        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            eventHandler = nil
            NSLog("KuroTools: could not register the global hotkey (%d) — probably taken by another app", registerStatus)
            return false
        }
        return true
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

/// Gộp một chuỗi ASCII tối đa 4 ký tự thành `FourCharCode`/`OSType` — kiểu
/// định danh cổ điển Carbon dùng khắp API cũ (chữ ký hotkey, loại tài
/// nguyên, v.v.).
private func fourCharCode(_ text: String) -> OSType {
    text.utf8.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
}
