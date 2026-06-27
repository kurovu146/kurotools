import AppKit
import SensorReader

public func formatBar(_ s: Snapshot, _ settings: Settings) -> String {
    var parts: [String] = []
    if settings.showTemp { parts.append("\(Int(s.cpuTempC.rounded()))°") }
    if settings.showCPU  { parts.append("\(Int(s.cpuLoadPct.rounded()))%") }
    if settings.showRAM  { parts.append(String(format: "%.1fG", s.ramUsedGB)) }
    if settings.showFan  { parts.append("🌀\(Int(s.fanRPM.rounded()))") }
    return parts.joined(separator: " ")
}

@MainActor
public final class MenuBarController {
    public let statusItem: NSStatusItem
    public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    }
    public func render(_ s: Snapshot, settings: Settings) {
        statusItem.button?.title = formatBar(s, settings)
    }
}

// MARK: - Dropdown menu

public extension MenuBarController {
    /// Builds (or rebuilds) the dropdown NSMenu and assigns it to `statusItem.menu`.
    /// Called by the app delegate on every tick so the menu always shows fresh data.
    ///
    /// - Parameters:
    ///   - s:             Latest sensor snapshot.
    ///   - settings:      Current user settings (used for Show-X states and threshold).
    ///   - target:        Action target for every interactive item.
    ///   - setRPM:        Action for the Apply button (and the rpmField return key).
    ///   - auto:          Action for "Auto (system)".
    ///   - presetQuiet:   Action for "Quiet (min RPM)".
    ///   - presetMax:     Action for "Max (full)".
    ///   - toggleShow:    Action for Show-X checkable items; sender.tag = 0:temp 1:cpu 2:ram 3:fan.
    ///   - setThreshold:  Action for threshold items; sender.tag = the °C value (90/95/100).
    ///   - quit:          Action for "Quit KuroVitals".
    ///   - rpmField:      The NSTextField instance owned by the caller; reused across rebuilds.
    func updateMenu(snapshot s: Snapshot,
                    settings: Settings,
                    target: AnyObject,
                    setRPM: Selector,
                    auto: Selector,
                    presetQuiet: Selector,
                    presetMax: Selector,
                    toggleShow: Selector,
                    setThreshold: Selector,
                    quit: Selector,
                    rpmField: NSTextField) {

        let menu = NSMenu()

        // ── 1. Disabled info rows ─────────────────────────────────────────────
        func info(_ text: String) {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        info(String(format: "CPU temp: %.0f°C", s.cpuTempC))
        info(String(format: "CPU load: %.0f%%", s.cpuLoadPct))
        info(String(format: "RAM: %.1f / %.0f GB", s.ramUsedGB, s.ramTotalGB))
        info(String(format: "Fan: %.0f rpm (%@)", s.fanRPM, s.fanForced ? "manual" : "auto"))
        info(String(format: "Range: %.0f–%.0f rpm", s.fanMin, s.fanMax))

        // ── 2. Separator ──────────────────────────────────────────────────────
        menu.addItem(.separator())

        // ── 3. RPM input row (custom NSView) ──────────────────────────────────
        let row = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))

        rpmField.frame = NSRect(x: 14, y: 3, width: 110, height: 22)
        rpmField.placeholderString = "RPM"
        rpmField.target = target
        rpmField.action = setRPM

        let apply = NSButton(frame: NSRect(x: 130, y: 1, width: 76, height: 26))
        apply.title = "Apply"
        apply.bezelStyle = .rounded
        apply.target = target
        apply.action = setRPM

        container.addSubview(rpmField)
        container.addSubview(apply)
        row.view = container
        menu.addItem(row)

        // ── 4. Fan presets + Auto ─────────────────────────────────────────────
        func fanItem(_ title: String, _ sel: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = target
            return item
        }
        menu.addItem(fanItem("Quiet (min RPM)", presetQuiet))
        menu.addItem(fanItem("Max (full)",      presetMax))
        menu.addItem(fanItem("Auto (system)",   auto))

        // ── 5. Separator ──────────────────────────────────────────────────────
        menu.addItem(.separator())

        // ── 6. Settings submenu ───────────────────────────────────────────────
        let settingsParent = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsMenu   = NSMenu(title: "Settings")

        // Show-X checkable items (tag = 0…3)
        let showRows: [(String, Bool, Int)] = [
            ("Show Temp", settings.showTemp, 0),
            ("Show CPU",  settings.showCPU,  1),
            ("Show RAM",  settings.showRAM,  2),
            ("Show Fan",  settings.showFan,  3),
        ]
        for (title, isOn, tag) in showRows {
            let item = NSMenuItem(title: title, action: toggleShow, keyEquivalent: "")
            item.state  = isOn ? .on : .off
            item.tag    = tag
            item.target = target
            settingsMenu.addItem(item)
        }

        settingsMenu.addItem(.separator())

        // Alert-threshold items — tag = °C value; active one has .on state
        let thresholdHeader = NSMenuItem(title: "Alert Threshold", action: nil, keyEquivalent: "")
        thresholdHeader.isEnabled = false
        settingsMenu.addItem(thresholdHeader)

        for degrees in [90, 95, 100] {
            let item = NSMenuItem(title: "\(degrees)°C", action: setThreshold, keyEquivalent: "")
            item.tag    = degrees
            item.state  = (Int(settings.thresholdC) == degrees) ? .on : .off
            item.target = target
            settingsMenu.addItem(item)
        }

        settingsParent.submenu = settingsMenu
        menu.addItem(settingsParent)

        // ── 7. Separator ──────────────────────────────────────────────────────
        menu.addItem(.separator())

        // ── 8. Quit ───────────────────────────────────────────────────────────
        let quitItem = NSMenuItem(title: "Quit KuroVitals", action: quit, keyEquivalent: "q")
        quitItem.target = target
        menu.addItem(quitItem)

        statusItem.menu = menu
    }
}
