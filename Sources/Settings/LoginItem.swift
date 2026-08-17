import Foundation
import ServiceManagement

/// `SMAppService.Status` thu gọn về đúng những gì UI cần phân biệt.
///
/// `.requiresApproval` là ca dễ bị bỏ sót nhất: `register()` không throw, macOS
/// tự xếp hàng "background item added" trong System Settings, và `status` trả
/// về `.requiresApproval` chứ KHÔNG phải `.enabled`. Một UI chỉ biết đọc
/// `isEnabled == true/false` sẽ thấy `false` và bật công tắc về lại off — người
/// dùng bấm mà như không có gì xảy ra, không có lời giải thích ở đâu cả.
public enum LoginItemState: Equatable {
    case off              // .notRegistered hoặc .notFound
    case on                // .enabled
    case requiresApproval  // đã đăng ký, đang chờ người dùng duyệt trong System Settings
}

public protocol LoginItemControlling {
    /// Đọc từ hệ thống mỗi lần, không nhớ trạng thái riêng: người dùng có thể
    /// tắt login item trong System Settings mà app không hề biết.
    var state: LoginItemState { get }
    func setEnabled(_ on: Bool) throws
}

public extension LoginItemControlling {
    /// Tiện dùng ở nơi chỉ cần bật/tắt nhị phân; `state` mới là hợp đồng thật.
    var isEnabled: Bool { state == .on }
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

    public var state: LoginItemState {
        // Liệt kê hết cả 4 case tay, KHÔNG dùng `default`/`@unknown default`: nếu
        // Apple thêm case mới thì phải vỡ build ở đây, không được âm thầm rơi
        // về `.off`.
        switch service.status {
        case .notRegistered: return .off
        case .enabled: return .on
        case .requiresApproval: return .requiresApproval
        case .notFound: return .off
        }
    }

    public func setEnabled(_ on: Bool) throws {
        if on {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
