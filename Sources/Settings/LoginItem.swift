import Foundation
import ServiceManagement

public protocol LoginItemControlling {
    /// Đọc từ hệ thống mỗi lần, không nhớ trạng thái riêng: người dùng có thể
    /// tắt login item trong System Settings mà app không hề biết.
    var isEnabled: Bool { get }
    func setEnabled(_ on: Bool) throws
}

/// Login item bằng `SMAppService.agent`, plist nằm trong
/// `KuroTools.app/Contents/Library/LaunchAgents/`.
///
/// Chọn `.agent` thay vì `.mainApp` để giữ `KeepAlive` chỉ-khi-crash — bản
/// LaunchAgent cài tay trước đây có tính chất đó, và mất nó nghĩa là app
/// chết lúc 9 giờ sáng thì nằm im tới lần đăng nhập sau.
public struct SMAppServiceLoginItem: LoginItemControlling {
    public static let plistName = "com.kuro.kurotools.app.plist"

    public init() {}

    private var service: SMAppService { .agent(plistName: Self.plistName) }

    public var isEnabled: Bool { service.status == .enabled }

    public func setEnabled(_ on: Bool) throws {
        if on {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
