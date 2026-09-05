KuroTools — theo dõi nhiệt độ/quạt, tra từ, hình nền video cho macOS
====================================================================

YÊU CẦU
  • Mac chạy Apple Silicon (M1/M2/M3/M4), macOS 13 trở lên.
  • Bản này build cho arm64. Mac Intel không chạy được.

CÀI
  1. Kéo KuroTools.app vào /Applications.
  2. Mở lần đầu: macOS sẽ chặn vì bản này KHÔNG được Apple công chứng
     (notarize) — xem mục "Vì sao macOS chặn" bên dưới.
     Vào  System Settings ▸ Privacy & Security,  kéo xuống cuối,
     bấm "Open Anyway" ở dòng nhắc tới KuroTools, rồi mở lại app.
  3. Muốn điều khiển quạt thì mở Terminal, cd vào thư mục này và chạy:
         ./install-helper.sh
     Script xin sudo để cài một LaunchDaemon chạy nền — ghi tốc độ quạt
     vào SMC là thao tác cần quyền root, app thường không làm được.
  4. Muốn dùng làm screensaver:
         ./install-saver.sh

  Không chạy install-helper.sh cũng dùng được: nhiệt độ, CPU, RAM, tra từ,
  hình nền video vẫn chạy đủ; chỉ phần chỉnh tốc độ quạt là không có.

GỠ
     ./uninstall-helper.sh     gỡ daemon quạt (quạt trở về Auto của hệ thống)
     ./uninstall-app.sh        gỡ app, screensaver, và video đã chép sang

VÌ SAO macOS CHẶN
  Công chứng phần mềm cần tài khoản Apple Developer trả phí. Dự án này
  không có, nên bản tải về chỉ ký ad-hoc và Gatekeeper cảnh báo rằng Apple
  chưa kiểm tra nó. Cảnh báo đó nói đúng: không ai kiểm tra thay bạn.
  Toàn bộ mã nguồn công khai tại github.com/kurovu146/kurotools — không
  tin thì tự build, README trong repo có hướng dẫn.

  Hệ quả nhỏ: mỗi bản cập nhật là một chữ ký khác, nên macOS sẽ hỏi lại
  quyền Accessibility (thứ mà phím tắt tra từ cần) sau khi bạn cập nhật.

ĐIỀU KHIỂN QUẠT — ĐỌC TRƯỚC KHI DÙNG
  Apple không hỗ trợ việc này; nó dựa trên các khoá SMC tìm ra bằng cách
  mò. Chỉ mới kiểm chứng thật trên MacBook Pro 14" M2 Pro.
  Máy nào SMC không trả lời khoá quạt thì app tự ẩn phần điều khiển quạt
  và nói rõ, chứ không hiện số bịa.
  Có ba lớp an toàn: tốc độ bị kẹp trong dải phần cứng cho phép; app tự
  trả quạt về Auto khi chạm ngưỡng nhiệt; daemon tự trả về Auto khi app
  tắt hoặc ngừng gửi nhịp. Dù vậy, dùng là tự chịu rủi ro — bảo vệ cuối
  cùng vẫn là cơ chế hạ xung theo nhiệt của chính firmware.

GIẤY PHÉP
  Apache License 2.0. Xem LICENSE trong repo.
