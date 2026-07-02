import AppKit
import SensorReader

/// The menu-bar label is a single "K" icon; all metrics live in the dropdown.
public let kMenuBarIcon = "K"

@MainActor
public final class MenuBarController {
    public let statusItem: NSStatusItem
    public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.boldSystemFont(ofSize: 14)
        statusItem.button?.title = kMenuBarIcon
    }

    /// Sets the bar title only when it actually changed — the title is "K" almost
    /// all the time, and re-setting it every tick triggers AppKit layout work.
    public func setTitle(_ title: String) {
        guard let button = statusItem.button, button.title != title else { return }
        button.title = title
    }
}

// MARK: - Dropdown menu

public extension MenuBarController {
    /// Rebuilds `menu` in place from the given snapshot.
    /// Called from NSMenuDelegate.menuNeedsUpdate — i.e. only when the user
    /// actually opens the dropdown, never on the sensor tick.
    ///
    /// - Parameters:
    ///   - menu:          The persistent status-item menu to (re)populate.
    ///   - s:             Latest sensor snapshot.
    ///   - settings:      Current user settings (used for Show-X states and threshold).
    ///   - target:        Action target for every interactive item.
    ///   - applyFanPreset: Action for a per-fan RPM submenu item; sender.tag = fan*100000 + rpm.
    ///   - autoFan:       Action for per-fan "Auto" button; sender.tag = fan index.
    ///   - allAuto:       Action for "Tất cả Auto" (revert all fans).
    ///   - presetQuiet:   Action for "Quiet (min) tất cả".
    ///   - presetMax:     Action for "Max tất cả".
    ///   - toggleShow:    Action for Show-X checkable items; sender.tag = 0:temp 1:cpu 2:ram 3:fan.
    ///   - setThreshold:  Action for threshold items; sender.tag = the °C value (90/95/100).
    ///   - quit:          Action for "Quit KuroVitals".
    func populate(menu: NSMenu,
                  snapshot s: Snapshot,
                  settings: Settings,
                  target: AnyObject,
                  applyFanPreset: Selector,
                  autoFan: Selector,
                  allAuto: Selector,
                  presetQuiet: Selector,
                  presetMax: Selector,
                  toggleShow: Selector,
                  setThreshold: Selector,
                  quit: Selector) {

        menu.removeAllItems()

        // ── 1. Disabled info rows ─────────────────────────────────────────────
        func info(_ text: String) {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if settings.showTemp { info(String(format: "CPU temp: %.0f°C", s.cpuTempC)) }
        if settings.showCPU  { info(String(format: "CPU load: %.0f%%", s.cpuLoadPct)) }
        if settings.showRAM  { info(String(format: "RAM: %.1f / %.0f GB", s.ramUsedGB, s.ramTotalGB)) }

        // ── 2. Separator ──────────────────────────────────────────────────────
        menu.addItem(.separator())

        // ── 3. Per-fan submenus (RPM presets) ─────────────────────────────────
        // NOTE: a text field inside an NSMenu can't receive typed input (the menu's
        // modal event tracking swallows keystrokes), so per-fan control is a submenu
        // of plain menu items — those fire their actions reliably.
        // tag encodes (fan, rpm) as `fan * 100000 + rpm` (rpm < 100000, fan small).
        let rpmStep = 500
        for (i, f) in s.fans.enumerated() {
            // Title shows actual rpm; when forced, also the requested target.
            let title = f.forced
                ? "Quạt \(i + 1): \(Int(f.rpm)) rpm → đặt \(Int(f.target))"
                : "Quạt \(i + 1): \(Int(f.rpm)) rpm (auto)"
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: "Quạt \(i + 1)")

            let autoItem = NSMenuItem(title: "Auto (hệ thống)", action: autoFan, keyEquivalent: "")
            autoItem.tag = i
            autoItem.target = target
            autoItem.state = f.forced ? .off : .on
            sub.addItem(autoItem)
            sub.addItem(.separator())

            // RPM steps from the first multiple of `rpmStep` ≥ min, up to (and incl.) max.
            let lo = Int((f.min / Double(rpmStep)).rounded(.up)) * rpmStep
            let hi = Int(f.max)
            var rpm = Swift.max(lo, rpmStep)
            while rpm < hi {
                let item = NSMenuItem(title: "\(rpm) rpm", action: applyFanPreset, keyEquivalent: "")
                item.tag = i * 100000 + rpm
                item.target = target
                if f.forced, abs(f.target - Double(rpm)) < Double(rpmStep) / 2 { item.state = .on }
                sub.addItem(item)
                rpm += rpmStep
            }
            if hi > 0 {
                let maxItem = NSMenuItem(title: "Max (\(hi) rpm)", action: applyFanPreset, keyEquivalent: "")
                maxItem.tag = i * 100000 + hi
                maxItem.target = target
                if f.forced, f.target >= Double(hi) - Double(rpmStep) / 2 { maxItem.state = .on }
                sub.addItem(maxItem)
            }

            parent.submenu = sub
            menu.addItem(parent)
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
        // Toggle which metric rows appear in this dropdown (fan rows are controls — always shown).
        let showRows: [(String, Bool, Int)] = [
            ("Show Temp", settings.showTemp, 0),
            ("Show CPU",  settings.showCPU,  1),
            ("Show RAM",  settings.showRAM,  2),
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
    }
}
