# KuroVitals — Thiết kế

- **Ngày**: 2026-06-27
- **Tác giả**: Kuro (cho anh Tuấn)
- **Trạng thái**: Đã duyệt thiết kế, chờ viết implementation plan
- **Máy đích**: MacBook Pro 14" — Apple M2 Pro (Mac14,9), macOS 26.5.1, 16GB RAM, 10 cores

## 1. Mục tiêu

Một app **menu bar (macOS) tự build bằng Swift native** hiển thị live ở góc trên bên phải màn hình:

- Nhiệt độ CPU (°C)
- CPU tải (%)
- RAM đang dùng (GB)
- Tốc độ quạt (RPM)

Và cho phép **điều khiển quạt bằng cách nhập RPM cụ thể** (kèm chế độ Auto trả về cho hệ thống tự quản).

Đây là tool cá nhân, chạy local trên 1 máy, không phân phối/notarize.

## 2. Bối cảnh kỹ thuật (Apple Silicon)

- Đọc **CPU% / RAM**: qua mach API (`host_statistics64`, `host_processor_info`) — không cần root.
- Đọc **nhiệt độ / fan RPM**: qua SMC (IOKit, service `AppleSMC`). Trên Apple Silicon thường đọc được ở quyền user (cần verify ở Spike #1).
- **Điều khiển quạt**: ghi SMC keys `F0Md` (mode: 0=auto, 1=forced) và `F0Tg` (target speed). Việc **ghi SMC cần quyền root** → bắt buộc một helper chạy root. Apple không hỗ trợ chính thức; tính khả thi được chứng minh bởi Macs Fan Control trên máy M-series có quạt, nhưng **các SMC key cụ thể phải tự xác nhận** trên M2 Pro.

> MacBook Pro 14" M2 Pro **có quạt** (active cooling) nên điều khiển quạt là khả thi.

## 3. Kiến trúc

Hai tiến trình, tách quyền:

```
┌─────────────────────────┐         XPC / Unix socket        ┌──────────────────────┐
│  KuroVitals.app (user)  │ ───── "set fan = 3000 rpm" ─────▶ │ Helper daemon (root) │
│  • NSStatusItem render  │ ◀──── "ok / current state" ────── │ • ghi SMC F0Md/F0Tg  │
│  • đọc CPU%/RAM (mach)   │                                   └──────────────────────┘
│  • đọc temp/fan (SMC RO) │
└─────────────────────────┘
```

- **GUI app** (quyền user): đọc số, render menu bar, gửi lệnh điều khiển, áp dụng logic an toàn.
- **Helper root**: chỉ làm đúng 1 việc — ghi SMC để set quạt. Tách ra để GUI không phải chạy root.
- **Cách cài helper**: quyết định ở Spike #1.
  - Ưu tiên: `SMAppService` (macOS 13+) nếu self-sign ad-hoc hoạt động.
  - Fallback: `LaunchDaemon` cài thủ công bằng script `sudo` (plist trong `/Library/LaunchDaemons`, binary trong `/usr/local/libexec`).

## 4. Module

| Module | Trách nhiệm | Phụ thuộc | Test được độc lập? |
|---|---|---|---|
| `SMCKit` | Mở `AppleSMC`, đọc/ghi SMC keys; parse kiểu dữ liệu (`flt`, `fpe2`, `ui16`...) | IOKit | Có — mock IOKit / test parser thuần |
| `SystemStats` | CPU% (delta tick), RAM dùng/tổng qua mach | — | Có — test tính toán từ snapshot giả |
| `SensorReader` | Gom: temp CPU, fan RPM (qua SMCKit) + CPU%/RAM (qua SystemStats) thành 1 snapshot | SMCKit, SystemStats | Có — mock 2 nguồn |
| `FanController` | Logic set RPM: clamp [min,max], chuyển Auto/Manual, safety guard quá nhiệt | SensorReader, HelperClient | Có — logic thuần, mock helper |
| `HelperClient` | Giao tiếp với helper daemon (XPC/socket) | — | Có — mock transport |
| `MenuBarController` | `NSStatusItem`: render text live, dropdown menu, timer ~1.5s | SensorReader, FanController | Manual chủ yếu |
| `Helper` (daemon, target riêng) | Nhận lệnh, ghi SMC quyền root | IOKit, SMCKit | Manual |

## 5. Luồng dữ liệu

1. Timer trong `MenuBarController` chạy mỗi ~1.5s → gọi `SensorReader.snapshot()`.
2. Snapshot gồm `{ cpuTempC, cpuLoadPct, ramUsedGB, ramTotalGB, fanRPM, fanMin, fanMax, mode }`.
3. `MenuBarController` cập nhật title `NSStatusItem` (compact) + nội dung dropdown.
4. User nhập RPM → `FanController.setTarget(rpm)`:
   - clamp vào `[fanMin, fanMax]`,
   - gọi `HelperClient.write(F0Md=1, F0Tg=rpm)`.
5. User bấm **Auto** → `FanController.setAuto()` → helper ghi `F0Md=0`.
6. Mỗi snapshot, `FanController.checkSafety(temp)`: nếu đang Manual và `temp >= threshold` → tự `setAuto()` + gửi notification.

## 6. An toàn (bắt buộc)

- **Auto-revert khi quá nhiệt**: ngưỡng mặc định **95°C** (cấu hình được). Đang Manual mà chạm ngưỡng → ép về Auto + `UNUserNotification` cảnh báo.
- **Clamp RPM**: luôn giới hạn trong `[F0Mn, F0Mx]` đọc từ SMC; không cho nhập số ngoài dải.
- **Trả Auto khi thoát/crash**: khi app `terminate` (và nếu khả thi, khi helper mất kết nối GUI quá N giây) → ghi `F0Md=0`. Không để quạt kẹt ở Manual khi app không còn giám sát.
- **Helper tối giản**: chỉ nhận đúng 2 thao tác (set target, set auto), validate đầu vào, không nhận lệnh tùy ý → giảm bề mặt tấn công của tiến trình root.

## 7. Hiển thị menu bar

- **Compact trên bar**: ví dụ `48° 12% 9.1G 🌀2400`. Mỗi mục bật/tắt được trong Settings (anh có thể chỉ để temp + fan nếu thấy dài).
- **Dropdown** (click vào):
  - Khối chi tiết: từng sensor + nhãn rõ ràng.
  - Ô **nhập RPM** + nút Áp dụng (có thể kèm vài preset nhanh: Quiet / Auto / Max).
  - Nút **Auto** (trả hệ thống tự quản) — luôn nổi bật.
  - Trạng thái mode hiện tại (Auto/Manual).
  - Settings… / Quit.

## 8. Spike #1 — Verify khả thi (làm TRƯỚC khi code app)

Trên chính M2 Pro của anh, xác nhận:

1. Liệt kê SMC keys tồn tại (qua một SMC reader nhỏ): tìm key fan (`F0Ac`, `F0Mn`, `F0Mx`, `F0Md`, `F0Tg`, `FNum`) và các key nhiệt độ CPU (`Tp..`/`Tc..` — tên sensor M2 Pro phải dò thực tế).
2. **Đọc** temp/fan có cần root không.
3. **Ghi** fan (`F0Md`/`F0Tg`) có cần root không, và có thực sự đổi tốc độ quạt không (test cẩn thận, set 1 mức an toàn rồi trả Auto ngay).
4. Kết quả → chốt: helper cài kiểu `SMAppService` hay `LaunchDaemon` thủ công.

Spike là điều kiện tiên quyết: nếu một bước bất khả thi, quay lại điều chỉnh thiết kế (vd: chỉ monitor nếu không ghi được).

## 9. Test & verify

- **Unit test** (XCTest):
  - `FanController`: clamp đúng biên, safety revert khi quá ngưỡng, chuyển Auto/Manual.
  - `SystemStats`: tính CPU% từ 2 snapshot tick, RAM used/total từ `vm_statistics64` giả.
  - `SMCKit`: parser các kiểu SMC (`fpe2`, `flt`, `ui16`) từ byte mẫu.
- **Verify thủ công**:
  - Số khớp Activity Monitor (CPU/RAM) và một nguồn nhiệt độ tham chiếu.
  - Nhập RPM → nghe/đo quạt thay đổi thật; bấm Auto → quạt trả về tự quản.
  - Test safety: ép RPM thấp khi tải nặng → khi chạm ngưỡng app phải tự trả Auto + báo.

## 10. Phân phối / cài đặt

- App self-sign ad-hoc, chạy local trên máy anh.
- Helper cài 1 lần bằng `sudo` (script `install-helper.sh`).
- Gỡ: script `uninstall-helper.sh` (xóa daemon, trả quạt về Auto).
- Không notarize, không lên store.

## 11. Quyết định mặc định (đổi được)

- Tên: **KuroVitals**.
- Vị trí code: `~/Dev/kurovitals`.
- Ngưỡng auto-revert: **95°C**.
- Refresh: **1.5s**.

## 12. Ngoài phạm vi (YAGNI)

- Đồ thị lịch sử / biểu đồ theo thời gian.
- Network/disk/GPU sensors.
- Quạt nhiều khu vực (M2 Pro MacBook chỉ 1–2 quạt; xử lý theo `FNum` thực tế, không over-engineer).
- Phân phối/notarize/auto-update.
- Đường cong quạt theo nhiệt độ tùy biến (fan curve) — có thể là v2.
