import AppKit
import SMCKit
import SystemStats
import SensorReader
import FanControl
import HelperProtocol

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var reader: SensorReader!
    private let menuBar = MenuBarController()
    private var fan: FanController!
    private var timer: Timer?
    private var settings = Settings.load()
    private var lastSnapshot: Snapshot?
    private var menuOpen = false
    private var warnUntil: Date?
    private var helperWarnUntil: Date?

    func applicationDidFinishLaunching(_ note: Notification) {
        guard let smc = try? SMC() else {
            let a = NSAlert()
            a.messageText = "KuroVitals"
            a.informativeText = "Cannot open SMC (AppleSMC). The app will quit."
            a.runModal()
            NSApp.terminate(nil)
            return
        }
        reader = SensorReader(smc: smc, cpu: CPULoadSampler(), mem: MemorySampler())
        fan = FanController(commander: HelperClient(), threshold: settings.thresholdC, ttlSeconds: 6)
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        let s = reader.snapshot()
        lastSnapshot = s

        let tickResult = fan.tick(currentTempC: s.cpuTempC)
        if tickResult.reverted {
            warnUntil = Date().addingTimeInterval(3)
            if let r = tickResult.response, !r.ok { flashHelperWarning() }
        }

        // Title priority: over-temp warning > helper warning > normal readout.
        if let until = warnUntil, until > Date() {
            menuBar.statusItem.button?.title = "⚠︎ Quá nhiệt → Auto"
        } else if let until = helperWarnUntil, until > Date() {
            menuBar.statusItem.button?.title = "⚠︎ Helper chưa cài?"
        } else {
            warnUntil = nil
            helperWarnUntil = nil
            menuBar.render(s, settings: settings)
        }

        if !menuOpen {
            menuBar.updateMenu(snapshot: s, settings: settings, target: self,
                applyFanPreset: #selector(applyFanPreset(_:)),
                autoFan: #selector(autoFan(_:)),
                allAuto: #selector(allAutoAction),
                presetQuiet: #selector(presetQuiet),
                presetMax: #selector(presetMax),
                toggleShow: #selector(toggleShow(_:)),
                setThreshold: #selector(setThreshold(_:)),
                quit: #selector(quitApp))
            menuBar.statusItem.menu?.delegate = self
        }
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    private func flashHelperWarning() {
        helperWarnUntil = Date().addingTimeInterval(3)
    }

    /// Rebuild the (now-dismissing) menu on the next runloop so a just-applied
    /// target shows its checkmark immediately, before the next ~1.5s tick.
    private func refreshSoon() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Sender tag encodes (fan, rpm) as `fan * 100000 + rpm` (set in updateMenu).
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
        refresh()
    }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        settings.thresholdC = Double(sender.tag)
        settings.save()
        fan.setThreshold(settings.thresholdC)
        refresh()
    }

    @objc private func quitApp() { _ = fan.setAllAuto(); NSApp.terminate(nil) }

    func applicationWillTerminate(_ note: Notification) { _ = fan?.setAllAuto() }
}
