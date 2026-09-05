Bản build sẵn cho **Apple Silicon (arm64), macOS 13+**.

### Cài
1. Tải file `.zip` bên dưới, giải nén, kéo `KuroTools.app` vào `/Applications`.
2. Mở lần đầu sẽ bị macOS chặn → *System Settings ▸ Privacy & Security* → **Open Anyway**.
3. Muốn chỉnh tốc độ quạt: `./install-helper.sh` (xin sudo, cài một LaunchDaemon — ghi SMC cần quyền root).
4. Muốn dùng screensaver: `./install-saver.sh`

Bỏ qua bước 3 vẫn dùng được nhiệt độ, CPU, RAM, tra từ và hình nền video.

### Vì sao macOS chặn
Bản này ký ad-hoc, không được Apple công chứng — công chứng cần tài khoản Apple Developer trả phí.
Cảnh báo của Gatekeeper nói đúng: không ai kiểm tra hộ bạn. Mã nguồn công khai trong repo này, không tin thì tự build.

### Lưu ý về điều khiển quạt
Dựa trên khoá SMC tìm ra bằng cách mò, Apple không hỗ trợ. Mới kiểm chứng trên MacBook Pro 14" M2 Pro.
Máy nào SMC không trả lời khoá quạt thì app tự ẩn phần điều khiển và nói rõ lý do, không hiện số bịa.
Dùng là tự chịu rủi ro.
