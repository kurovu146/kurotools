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
    private let rpmField = NSTextField(string: "")
    private var lastSnapshot: Snapshot?
    private var menuOpen = false
    private var warnUntil: Date?

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
        rpmField.placeholderString = "RPM"
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        let s = reader.snapshot()
        lastSnapshot = s
        let reverted = fan.tick(currentTempC: s.cpuTempC, currentlyForced: s.fanForced)
        if reverted { warnUntil = Date().addingTimeInterval(3) }
        if let until = warnUntil, until > Date() {
            menuBar.statusItem.button?.title = "⚠︎ Quá nhiệt → Auto"
        } else {
            warnUntil = nil
            menuBar.render(s, settings: settings)
        }
        if !menuOpen {
            menuBar.updateMenu(snapshot: s, settings: settings, target: self,
                setRPM: #selector(applyRPM), auto: #selector(setAutoAction),
                presetQuiet: #selector(presetQuiet), presetMax: #selector(presetMax),
                toggleShow: #selector(toggleShow(_:)), setThreshold: #selector(setThreshold(_:)),
                quit: #selector(quitApp), rpmField: rpmField)
            menuBar.statusItem.menu?.delegate = self
        }
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    @objc private func applyRPM() {
        guard let s = lastSnapshot, let rpm = Int(rpmField.stringValue) else { return }
        let applied = fan.setTarget(rpm: rpm, min: Int(s.fanMin), max: Int(s.fanMax))
        rpmField.stringValue = String(applied)
    }
    @objc private func presetQuiet() {
        guard let s = lastSnapshot else { return }
        _ = fan.setTarget(rpm: Int(s.fanMin), min: Int(s.fanMin), max: Int(s.fanMax))
    }
    @objc private func presetMax() {
        guard let s = lastSnapshot else { return }
        _ = fan.setTarget(rpm: Int(s.fanMax), min: Int(s.fanMin), max: Int(s.fanMax))
    }
    @objc private func setAutoAction() { fan.setAuto() }
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
    @objc private func quitApp() { fan.setAuto(); NSApp.terminate(nil) }

    func applicationWillTerminate(_ note: Notification) { fan?.setAuto() }
}
