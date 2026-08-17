import Darwin
import Foundation

/// Tiến trình NÀY có đang giữ một file cụ thể mở không.
///
/// Sinh ra cho đúng một câu hỏi mà `StoreMaintaining.canRead()` một mình
/// không trả lời được (giới hạn ghi trong review Task 5): một phép đọc thành
/// công chứng minh store còn SỐNG, không chứng minh nó đang đọc ĐÚNG FILE
/// vừa được mở — nếu `closeStore()` báo thành công mà thực ra chưa đóng, thì
/// `kt_init` là no-op thành công và mọi phép đọc sau đó trúng db CŨ, "qua"
/// y hệt.
///
/// So theo **(device, inode)**, không theo chuỗi đường dẫn: cùng một file có
/// thể mang nhiều tên (`/var/folders/…` và `/private/var/folders/…` — đã đo
/// trên máy này: `resolvingSymlinksInPath()` KHÔNG chuẩn hoá về nhau), và so
/// chuỗi sẽ báo "không mở" cho đúng file đang mở, tức từ chối mọi lần đổi chỗ
/// db hợp lệ.
///
/// Giới hạn còn lại, cố ý không giấu: nó chứng minh **tiến trình** đang giữ
/// file, không chứng minh **store của Rust** là thứ đang giữ nó. Bằng chứng
/// mạnh hơn thế cần một hàm FFI mới trả về đường dẫn `Store` đang mở, nằm
/// ngoài phạm vi task này.
enum OpenFileProbe {
    /// `true`/`false` là câu trả lời thật; `nil` là "không đo được" (libproc
    /// từ chối) — caller phải coi `nil` là KHÔNG kết luận gì, đừng biến sự
    /// bất lực của phép đo thành một lời từ chối.
    static func processHasOpen(_ url: URL, pid: pid_t = getpid()) -> Bool? {
        var target = stat()
        guard stat(url.path, &target) == 0 else { return false }

        let sizeNeeded = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard sizeNeeded > 0 else { return nil }
        // Dư 32 slot: số fd có thể tăng giữa hai lời gọi `proc_pidinfo`, và
        // một buffer vừa khít sẽ âm thầm cắt cụt danh sách — đúng chỗ file
        // cần tìm có thể nằm.
        let capacity = Int(sizeNeeded) / MemoryLayout<proc_fdinfo>.stride + 32
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
        let used = proc_pidinfo(
            pid, PROC_PIDLISTFDS, 0, &descriptors,
            Int32(capacity * MemoryLayout<proc_fdinfo>.stride))
        guard used > 0 else { return nil }

        for index in 0..<(Int(used) / MemoryLayout<proc_fdinfo>.stride) {
            let descriptor = descriptors[index]
            guard descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) else { continue }
            var info = vnode_fdinfowithpath()
            let read = proc_pidfdinfo(
                pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info,
                Int32(MemoryLayout<vnode_fdinfowithpath>.size))
            // fd có thể đã đóng giữa lúc liệt kê và lúc hỏi chi tiết — bỏ qua,
            // không phải lỗi của cả phép đo.
            guard read > 0 else { continue }
            let vnode = info.pvip.vip_vi.vi_stat
            if vnode.vst_ino == UInt64(target.st_ino) && vnode.vst_dev == target.st_dev {
                return true
            }
        }
        return false
    }
}
