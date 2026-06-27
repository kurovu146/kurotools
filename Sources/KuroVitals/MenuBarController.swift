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
    ///   - applyFan:      Action for per-fan Apply button and field enter key; sender.tag = fan index.
    ///   - autoFan:       Action for per-fan "Auto" button; sender.tag = fan index.
    ///   - allAuto:       Action for "Tất cả Auto" (revert all fans).
    ///   - presetQuiet:   Action for "Quiet (min) tất cả".
    ///   - presetMax:     Action for "Max tất cả".
    ///   - toggleShow:    Action for Show-X checkable items; sender.tag = 0:temp 1:cpu 2:ram 3:fan.
    ///   - setThreshold:  Action for threshold items; sender.tag = the °C value (90/95/100).
    ///   - quit:          Action for "Quit KuroVitals".
    ///   - rpmFields:     NSTextField instances owned by the caller; one per fan, indexed by fan.
    func updateMenu(snapshot s: Snapshot,
                    settings: Settings,
                    target: AnyObject,
                    applyFan: Selector,
                    autoFan: Selector,
                    allAuto: Selector,
                    presetQuiet: Selector,
                    presetMax: Selector,
                    toggleShow: Selector,
                    setThreshold: Selector,
                    quit: Selector,
                    rpmFields: [NSTextField]) {

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

        // ── 2. Separator ──────────────────────────────────────────────────────
        menu.addItem(.separator())

        // ── 3. Per-fan rows ───────────────────────────────────────────────────
        for (i, f) in s.fans.enumerated() {
            // Disabled info row for this fan
            let modeLabel = f.forced ? "tay" : "auto"
            info("Quạt \(i + 1): \(Int(f.rpm)) rpm (\(modeLabel)) · \(Int(f.min))–\(Int(f.max))")

            // Input row (custom NSView) — only if we have an rpmField for this fan
            guard i < rpmFields.count else { continue }
            let field = rpmFields[i]
            let row = NSMenuItem()
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 28))

            field.frame = NSRect(x: 14, y: 3, width: 110, height: 22)
            field.placeholderString = "RPM"
            field.tag = i
            field.target = target
            field.action = applyFan

            let applyBtn = NSButton(frame: NSRect(x: 130, y: 1, width: 66, height: 26))
            applyBtn.title = "Áp dụng"
            applyBtn.bezelStyle = .rounded
            applyBtn.tag = i
            applyBtn.target = target
            applyBtn.action = applyFan

            let autoBtn = NSButton(frame: NSRect(x: 200, y: 1, width: 52, height: 26))
            autoBtn.title = "Auto"
            autoBtn.bezelStyle = .rounded
            autoBtn.tag = i
            autoBtn.target = target
            autoBtn.action = autoFan

            container.addSubview(field)
            container.addSubview(applyBtn)
            container.addSubview(autoBtn)
            row.view = container
            menu.addItem(row)
        }

        // ── 4. Separator + global fan controls ───────────────────────────────
        menu.addItem(.separator())

        func globalItem(_ title: String, _ sel: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = target
            return item
        }
        menu.addItem(globalItem("Tất cả Auto", allAuto))
        menu.addItem(globalItem("Quiet (min) tất cả", presetQuiet))
        menu.addItem(globalItem("Max tất cả", presetMax))

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
