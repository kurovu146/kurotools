import AVFoundation
import AppKit
import ScreenSaver

/// Screensaver phát video mà app đã đặt vào container.
///
/// `@objc(KTWallpaperSaverView)` KHÔNG được bỏ: `NSPrincipalClass` trong
/// Info.plist là một chuỗi, còn tên ObjC của class Swift mặc định bị mangle
/// theo module (`_TtC…`). Bỏ nó đi thì engine nạp bundle xong không tìm ra
/// class và chỉ báo một lỗi chung chung.
///
/// KHÔNG lặp qua `NSScreen.screens` như `VideoWallpaperController`:
/// `ScreenSaverEngine` đã tạo sẵn một instance view cho mỗi màn hình.
@objc(KTWallpaperSaverView)
public final class KTWallpaperSaverView: ScreenSaverView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        // Không vẽ theo frame — AVPlayerLayer tự lo. Để nhịp thưa cho engine
        // khỏi gọi `animateOneFrame` vô ích.
        animationTimeInterval = 1.0
        wantsLayer = true
        buildPlayerIfVideoExists()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    public override func startAnimation() {
        super.startAnimation()
        player?.play()
    }

    public override func stopAnimation() {
        super.stopAnimation()
        player?.pause()
    }

    /// Chưa chọn video thì vẽ nền đen + một dòng chỉ đường. Đây cũng là thứ
    /// hiện trong ô preview của System Settings trước lần chọn đầu tiên — màn
    /// hình trắng trơn ở đó không nói cho ai biết phải làm gì.
    public override func draw(_ rect: NSRect) {
        guard playerLayer == nil else { return }
        NSColor.black.setFill()
        rect.fill()

        let text = "KuroTools — chọn video trong Settings ▸ Chung"
        let size = max(14, bounds.height * 0.03)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.65),
        ]
        let measured = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - measured.width / 2,
                        y: bounds.midY - measured.height / 2),
            withAttributes: attributes)
    }

    private func buildPlayerIfVideoExists() {
        guard let url = SaverVideoLocator.findInDefaultLocation() else { return }

        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.volume = 0
        let loop = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))

        let layer = AVPlayerLayer(player: queue)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        self.layer?.addSublayer(layer)

        player = queue
        looper = loop
        playerLayer = layer
    }
}
