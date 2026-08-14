import AppKit
import SwiftUI

/// Đo chiều cao "tự nhiên" mà `view` cần cho nội dung của nó, kẹp trong
/// `range`. Đối chiếu với `useHeightFitsContent` ở
/// `~/Dev/ktranslate/src/window.ts`: cùng bài toán (panel co giãn theo nội
/// dung như Look Up của hệ thống), khác nền tảng đo.
///
/// Dùng `frame.height` của chính `view` — với điều kiện `view` là phần tử NỘI
/// DUNG, không phải scroll container bọc ngoài nó. Một `NSHostingView` không
/// bị ép giãn theo constraint của cha (đây chính là trường hợp gọi hàm này
/// cho) tự đặt `frame` của nó bằng kích thước tự nhiên SwiftUI muốn sau mỗi
/// lượt layout, nên `frame.height` của NÓ đã là câu trả lời.
///
/// Ngược lại, `frame.height` của scroll container luôn là khung ta ÁP ĐẶT từ
/// trước (kích thước cửa sổ ta đã gán lần trước) — đo nhầm chỗ đó thì panel
/// chỉ phình ra chứ không bao giờ co lại theo nội dung ngắn hơn, vì phép đo
/// đang đo lại chính kết quả của lần đo trước.
public func measuredHeight(of view: NSView, clampedTo range: ClosedRange<CGFloat>) -> CGFloat {
    min(max(view.frame.height, range.lowerBound), range.upperBound)
}

/// `NSHostingView` mà việc kéo panel chính là bản thân nó — popup không có
/// titlebar để làm tay cầm, nên panel phải là tay cầm.
///
/// Chỉ bắt ở `mouseDown`, không phải toàn bộ vùng: AppKit định tuyến sự kiện
/// tới subview khớp `hitTest` trước khi rơi tới `super`/view cha, nên bất kỳ
/// phần tử con nào tự nhận sự kiện chuột — nút bấm, hay text được đánh dấu
/// `.textSelection(.enabled)` để bôi đen/copy được (senses, bản dịch) — vẫn
/// nhận click của riêng nó và không bao giờ tới đây. Phần còn lại (nền panel,
/// hàng headword — chữ ở đó vốn đã được chọn sẵn trong app nó đến từ) rơi
/// đúng vào override này và kéo cả cửa sổ.
///
/// `performDrag` hand thẳng gesture cho window server: không có ngưỡng kéo
/// phải chờ, và không có cách đổi ý giữa chừng — nên không gọi `super`, tránh
/// hai nơi cùng xử lý một cú mousedown.
@MainActor
public final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    public override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
