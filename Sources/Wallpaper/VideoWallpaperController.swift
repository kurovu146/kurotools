import AppKit
import AVFoundation
import CoreGraphics

/// Những gì Settings/AppDelegate cần từ hình nền video. Protocol để
/// `SettingsModel` nhận được một test double — cửa sổ + AVPlayer không dựng
/// được trong test.
@MainActor
public protocol WallpaperControlling: AnyObject {
    var isEnabled: Bool { get }
    var videoURL: URL? { get }
    func setEnabled(_ on: Bool)
    func setVideo(_ url: URL?)
}

/// Stub mặc định: `SettingsModel` dựng cho test (và mọi nơi không cần wallpaper
/// thật) không được phép chạm cửa sổ/AVPlayer.
@MainActor
public final class NoopWallpaper: WallpaperControlling {
    public var isEnabled: Bool { false }
    public var videoURL: URL? { nil }
    public func setEnabled(_ on: Bool) {}
    public func setVideo(_ url: URL?) {}
    public init() {}
}

/// Một cửa sổ hình nền video trên MỘT màn hình: borderless, nằm ở desktop
/// window level (SAU icons — đo: `kCGDesktopWindowLevel = -2147483623`,
/// `kCGDesktopIconWindowLevel = -2147483603`), click-through, ở mọi Space và
/// cả fullscreen space (`.fullScreenAuxiliary`).
@MainActor
public final class VideoWallpaperController: WallpaperControlling {
    private struct WallpaperWindow {
        let window: NSWindow
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
        /// `NSScreen.frame` lúc dựng — cần để hỏi riêng cho TỪNG màn hình
        /// "màn này có đang bị che không".
        let screenFrame: CGRect
        var isPlaying: Bool
    }

    private let store: WallpaperSettingsStore
    private var windows: [WallpaperWindow] = []
    /// Token chống App Nap khi wallpaper đang bật — App Nap làm AVPlayer rớt
    /// nhịp giữa chừng dù màn hình vẫn bật. KHÔNG chống idle sleep: máy vẫn
    /// ngủ bình thường, chỉ là lúc đang thức video phải chạy đều.
    private var napToken: NSObjectProtocol?
    /// Poll thay vì notification: `NSWindow.occlusionState` không dùng được ở
    /// desktop level (xem `PlaybackGate`), và nguồn điện thì gộp luôn vào đây
    /// cho đỡ một cơ chế nữa. 2s đủ nhạy mà rẻ hơn nhiều so với decode video.
    private var pollTimer: Timer?
    private static let pollSeconds: TimeInterval = 2

    public private(set) var isEnabled: Bool
    public private(set) var videoURL: URL?

    public init(store: WallpaperSettingsStore = WallpaperSettingsStore()) {
        self.store = store
        let loaded = store.load()
        isEnabled = loaded.enabled
        videoURL = loaded.videoURL
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        pollTimer?.invalidate()
        for w in windows { w.player.pause() }
    }

    /// Gọi lúc app khởi động: đưa cửa sổ về đúng trạng thái đã lưu.
    public func restore() {
        rebuild()
    }

    public func setEnabled(_ on: Bool) {
        isEnabled = on
        store.save(WallpaperSettings(videoURL: videoURL, enabled: on))
        rebuild()
    }

    public func setVideo(_ url: URL?) {
        videoURL = url
        store.save(WallpaperSettings(videoURL: url, enabled: isEnabled))
        rebuild()
    }

    // MARK: - Cửa sổ wallpaper

    /// Dựng lại toàn bộ theo trạng thái hiện tại. Gọi ở mọi điểm đổi trạng
    /// thái — phá rồi dựng lại là đủ đơn giản và chính xác cho 1-2 màn hình.
    private func rebuild() {
        teardownWindows()
        guard isEnabled, let url = videoURL,
              FileManager.default.fileExists(atPath: url.path) else {
            stopPolling()
            endNapPrevention()
            return
        }
        buildWindows(url: url)
        startPolling()
        // Đặt trạng thái đúng NGAY, không đợi tick đầu — nếu không thì mỗi lần
        // đổi video sẽ phát 2 giây rồi mới dừng dù đang bị che hoặc chạy pin.
        updatePlayback()
    }

    private func buildWindows(url: URL) {
        for screen in NSScreen.screens {
            let player = AVQueuePlayer()
            let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            player.isMuted = true
            player.volume = 0

            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

            let content = NSView(frame: screen.frame)
            content.wantsLayer = true
            playerLayer.frame = content.bounds
            content.layer?.addSublayer(playerLayer)

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.animationBehavior = .none
            window.contentView = content
            window.orderFrontRegardless()

            // KHÔNG play ở đây: `updatePlayback()` ngay sau `buildWindows`
            // mới là chỗ quyết định, tránh nháy một nhịp rồi dừng.
            windows.append(WallpaperWindow(window: window, player: player, looper: looper,
                                           screenFrame: screen.frame, isPlaying: false))
        }
    }

    private func teardownWindows() {
        stopPolling()
        for w in windows {
            w.player.pause()
            w.looper.disableLooping()
            w.window.orderOut(nil)
            w.window.contentView = nil
        }
        windows = []
    }

    // MARK: - Tạm dừng khi không ai nhìn / khi chạy pin

    private func startPolling() {
        guard pollTimer == nil else { return }
        let t = Timer(timeInterval: Self.pollSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePlayback() }
        }
        t.tolerance = Self.pollSeconds * 0.5
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Một lượt đo: màn nào đang bị che, máy có đang chạy pin. Chỉ gọi
    /// `play()`/`pause()` khi trạng thái THỰC SỰ đổi.
    private func updatePlayback() {
        guard !windows.isEmpty else { return }
        let onBattery = PlaybackGate.isOnBattery(
            powerSourceType: PlaybackGate.currentPowerSourceType())
        let infos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let onScreen = PlaybackGate.parse(infos)
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let wallpaperLayer = Int(CGWindowLevelForKey(.desktopWindow))

        var anyPlaying = false
        for i in windows.indices {
            let covered = PlaybackGate.isCovered(
                onScreen,
                screenFrame: PlaybackGate.flip(windows[i].screenFrame, primaryTop: primaryTop),
                aboveLayer: wallpaperLayer)
            let want = PlaybackGate.shouldPlay(enabled: isEnabled, hasVideo: videoURL != nil,
                                               covered: covered, onBattery: onBattery)
            if want != windows[i].isPlaying {
                if want { windows[i].player.play() } else { windows[i].player.pause() }
                windows[i].isPlaying = want
            }
            anyPlaying = anyPlaying || want
        }
        // Không phát thì không giữ máy thức hộ ai.
        if anyPlaying { beginNapPrevention() } else { endNapPrevention() }
    }

    private func beginNapPrevention() {
        guard napToken == nil else { return }
        napToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "KuroTools video wallpaper")
    }

    private func endNapPrevention() {
        if let token = napToken {
            ProcessInfo.processInfo.endActivity(token)
            napToken = nil
        }
    }

    @objc private func screensChanged() {
        guard isEnabled else { return }
        rebuild()
    }
}
