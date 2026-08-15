import AppKit
import SMCKit
import SystemStats
import SensorReader
import FanControl
import HelperProtocol

@MainActor
public final class VitalsController: NSObject, NSMenuDelegate {
    private var reader: SensorReader!
    private let menuBar = MenuBarController()
    private lazy var processWindowController = ProcessWindowController()
    private var fan: FanController!
    private var timer: Timer?
    private var settings = Settings.load()
    private var lastSnapshot: Snapshot?
    private var menuOpen = false
    private var warnUntil: Date?
    private var helperWarnUntil: Date?

    /// Tick interval while the dropdown is open — fast enough to feel live.
    private let menuOpenRefreshSeconds: TimeInterval = 1.0

    /// Menu giờ dùng chung với module Translate, nên chủ sở hữu menu là
    /// AppDelegate của KuroTools chứ không phải controller này.
    public var extraItems: [NSMenuItem] = []

    /// Returns whether startup actually succeeded. `NSApp.terminate(nil)` on
    /// the failure path is ASYNCHRONOUS — it only schedules the quit, it does
    /// not stop execution here — so the caller must check this before doing
    /// anything else that assumes a live app (minor, final review): without
    /// it, AppDelegate used to plough on into `translate.start(...)` on a
    /// machine that is about to quit, registering the global hotkey, running
    /// the database migration, and opening SQLite for no reason.
    public func start() -> Bool {
        guard let smc = try? SMC() else {
            let a = NSAlert()
            a.messageText = "KuroTools"
            a.informativeText = "Cannot open SMC (AppleSMC). The app will quit."
            a.runModal()
            NSApp.terminate(nil)
            return false
        }
        reader = SensorReader(smc: smc, cpu: CPULoadSampler(), mem: MemorySampler())
        fan = FanController(commander: HelperClient(), threshold: settings.thresholdC, ttlSeconds: 6)

        startNormalTimer()

        // Warm the SMC key/info caches so the first menu open is instant.
        lastSnapshot = reader.snapshot()
        return true
    }

    /// Menu giờ dùng chung với module Translate, nên chủ sở hữu menu là
    /// AppDelegate của KuroTools chứ không phải controller này.
    public func attach(menu: NSMenu) {
        menu.delegate = self
        menuBar.statusItem.menu = menu
    }

    /// Reverts fans to auto on any termination path, not just the "Quit"
    /// menu item — e.g. system shutdown/logout also sends this to accessory
    /// apps. Forwarded from KuroTools' AppDelegate.applicationWillTerminate.
    public func stop() {
        _ = fan?.setAllAuto()
    }

    /// (Re)schedules the tick in RunLoop mode .common — unlike scheduledTimer's
    /// .default mode, .common includes .eventTracking, so ticks keep firing
    /// while the dropdown menu is open (live metrics + fan heartbeat).
    private func startTimer(interval: TimeInterval, tolerance: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = tolerance
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Normal cadence with generous tolerance — the OS may coalesce our wakeup.
    private func startNormalTimer() {
        startTimer(interval: settings.refreshSeconds, tolerance: settings.refreshSeconds * 0.25)
    }

    private func refresh() {
        // Idle fast-path: menu closed, no manual fan to heartbeat, and no
        // warning banner to expire. The bar shows the static "K" and the
        // dropdown reads a fresh snapshot when opened, so there is nothing to
        // compute — skip all SMC/mach reads. This is the app's state almost
        // all of the time.
        if !menuOpen && !fan.hasManualTargets && warnUntil == nil && helperWarnUntil == nil { return }

        let s = reader.snapshot()
        lastSnapshot = s

        let tickResult = fan.tick(currentTempC: s.cpuTempC)
        if tickResult.reverted {
            warnUntil = Date().addingTimeInterval(3)
            if let r = tickResult.response, !r.ok { flashHelperWarning() }
        }

        // Title priority: over-temp warning > helper warning > normal "K" icon.
        let now = Date()
        if let until = warnUntil, until > now {
            menuBar.setTitle("⚠︎ Quá nhiệt → Auto")
        } else if let until = helperWarnUntil, until > now {
            menuBar.setTitle("⚠︎ Helper chưa cài?")
        } else {
            warnUntil = nil
            helperWarnUntil = nil
            menuBar.setTitle(kMenuBarIcon)
        }

        // While the dropdown is open, refresh its rows in place so the metrics
        // are live, not a snapshot from the moment it was opened.
        if menuOpen { menuBar.updateLive(snapshot: s) }
    }

    public func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        startTimer(interval: menuOpenRefreshSeconds, tolerance: 0.1)
    }

    public func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        startNormalTimer()
    }

    /// Called by AppKit right before the dropdown opens — build it from a fresh
    /// snapshot so RPM/temp/checkmarks are current without any per-tick rebuild.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        let s = reader.snapshot()
        lastSnapshot = s
        menuBar.populate(menu: menu, snapshot: s, settings: settings, target: self,
            applyFanPreset: #selector(applyFanPreset(_:)),
            autoFan: #selector(autoFan(_:)),
            allAuto: #selector(allAutoAction),
            presetQuiet: #selector(presetQuiet),
            presetMax: #selector(presetMax),
            toggleShow: #selector(toggleShow(_:)),
            setThreshold: #selector(setThreshold(_:)),
            showProcesses: #selector(showProcesses),
            quit: #selector(quitApp))

        if !extraItems.isEmpty {
            // menuBar.populate() always ends with "Quit" as the last item —
            // insert ahead of it instead of appending, so extra items read as
            // part of the menu body (macOS convention keeps Quit last).
            let quitIndex = menu.items.count - 1
            menu.insertItem(.separator(), at: quitIndex)
            for (offset, item) in extraItems.enumerated() {
                menu.insertItem(item, at: quitIndex + 1 + offset)
            }
        }
    }

    private func flashHelperWarning() {
        helperWarnUntil = Date().addingTimeInterval(3)
    }

    /// Run a tick on the next runloop so a just-applied change is reflected
    /// (heartbeat + warning title) before the next timer firing.
    private func refreshSoon() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Sender tag encodes (fan, rpm) as `fan * 100000 + rpm` (set in populate).
    @objc private func applyFanPreset(_ sender: NSMenuItem) {
        let fanIdx = sender.tag / 100000
        let rpm = sender.tag % 100000
        guard let s = lastSnapshot, fanIdx >= 0, fanIdx < s.fans.count else { return }
        let f = s.fans[fanIdx]
        let (_, resp) = fan.setTarget(fan: fanIdx, rpm: rpm, min: Int(f.min), max: Int(f.max))
        if !resp.ok { flashHelperWarning() }
        refreshSoon()
    }

    @objc private func autoFan(_ sender: NSMenuItem) {
        guard let s = lastSnapshot, sender.tag >= 0, sender.tag < s.fans.count else { return }
        let r = fan.setAuto(fan: sender.tag)
        if !r.ok { flashHelperWarning() }
        refreshSoon()
    }

    @objc private func allAutoAction() {
        let r = fan.setAllAuto()
        if !r.ok { flashHelperWarning() }
        refreshSoon()
    }

    @objc private func presetQuiet() {
        guard let s = lastSnapshot else { return }
        var anyFail = false
        for f in s.fans {
            let (_, resp) = fan.setTarget(fan: f.index, rpm: Int(f.min), min: Int(f.min), max: Int(f.max))
            if !resp.ok { anyFail = true }
        }
        if anyFail { flashHelperWarning() }
        refreshSoon()
    }

    @objc private func presetMax() {
        guard let s = lastSnapshot else { return }
        var anyFail = false
        for f in s.fans {
            let (_, resp) = fan.setTarget(fan: f.index, rpm: Int(f.max), min: Int(f.min), max: Int(f.max))
            if !resp.ok { anyFail = true }
        }
        if anyFail { flashHelperWarning() }
        refreshSoon()
    }

    @objc private func toggleShow(_ sender: NSMenuItem) {
        switch sender.tag {
        case 0: settings.showTemp.toggle()
        case 1: settings.showCPU.toggle()
        case 2: settings.showRAM.toggle()
        case 3: settings.showFan.toggle()
        default: break
        }
        settings.save()
    }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        settings.thresholdC = Double(sender.tag)
        settings.save()
        fan.setThreshold(settings.thresholdC)
    }

    @objc private func showProcesses() {
        processWindowController.showAndRefresh()
    }

    @objc private func quitApp() { _ = fan.setAllAuto(); NSApp.terminate(nil) }
}
