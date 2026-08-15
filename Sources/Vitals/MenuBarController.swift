import AppKit
import SensorReader

/// The menu-bar label is a single "K" icon; all metrics live in the dropdown.
public let kMenuBarIcon = "K"

@MainActor
public final class MenuBarController {
    public let statusItem: NSStatusItem

    // References into the currently populated menu, so ticks that fire while
    // the menu is open can update titles/checkmarks in place. Rebuilding the
    // menu while it's open would close any hovered submenu and flicker.
    private struct LiveFanItems {
        let parent: NSMenuItem
        let autoItem: NSMenuItem
        let presetItems: [NSMenuItem]   // RPM presets incl. Max; rpm = tag % 100000
    }
    private var liveTempItem: NSMenuItem?
    private var liveCPUItem: NSMenuItem?
    private var liveRAMItem: NSMenuItem?
    private var liveFans: [LiveFanItems] = []

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

    // MARK: Shared row formatting (populate + updateLive must never drift apart)

    static let rpmStep = 500

    static func tempTitle(_ s: Snapshot) -> String { String(format: "CPU temp: %.0f°C", s.cpuTempC) }
    static func cpuTitle(_ s: Snapshot) -> String { String(format: "CPU load: %.0f%%", s.cpuLoadPct) }
    static func ramTitle(_ s: Snapshot) -> String {
        String(format: "RAM: %.1f / %.0f GB", s.ramUsedGB, s.ramTotalGB)
    }
    /// Title shows actual rpm; when forced, also the requested target.
    static func fanTitle(_ i: Int, _ f: FanReading) -> String {
        f.forced
            ? "Quạt \(i + 1): \(Int(f.rpm)) rpm → đặt \(Int(f.target))"
            : "Quạt \(i + 1): \(Int(f.rpm)) rpm (auto)"
    }
    /// Checkmark when the fan is forced to (about) this preset's rpm.
    static func presetState(_ f: FanReading, presetRPM: Int) -> NSControl.StateValue {
        (f.forced && abs(f.target - Double(presetRPM)) < Double(rpmStep) / 2) ? .on : .off
    }

    /// Refreshes titles/checkmarks of the already-built menu in place.
    /// Called on each tick while the menu is open.
    public func updateLive(snapshot s: Snapshot) {
        liveTempItem?.title = Self.tempTitle(s)
        liveCPUItem?.title = Self.cpuTitle(s)
        liveRAMItem?.title = Self.ramTitle(s)
        // Fan count is constant for a boot session; a mismatch means the menu
        // is stale mid-rebuild — skip rather than index out of bounds.
        guard s.fans.count == liveFans.count else { return }
        for (i, f) in s.fans.enumerated() {
            let live = liveFans[i]
            live.parent.title = Self.fanTitle(i, f)
            live.autoItem.state = f.forced ? .off : .on
            for item in live.presetItems {
                item.state = Self.presetState(f, presetRPM: item.tag % 100000)
            }
        }
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
    ///   - showProcesses: Action for opening the running-process inspector.
    ///   - quit:          Action for "Quit KuroTools".
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
                  showProcesses: Selector,
                  quit: Selector) {

        menu.removeAllItems()
        liveTempItem = nil
        liveCPUItem = nil
        liveRAMItem = nil
        liveFans = []

        // ── 1. Disabled info rows ─────────────────────────────────────────────
        func info(_ text: String) -> NSMenuItem {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return item
        }
        if settings.showTemp { liveTempItem = info(Self.tempTitle(s)) }
        if settings.showCPU  { liveCPUItem  = info(Self.cpuTitle(s)) }
        if settings.showRAM  { liveRAMItem  = info(Self.ramTitle(s)) }

        // ── 2. Separator ──────────────────────────────────────────────────────
        menu.addItem(.separator())

        // ── 3. Per-fan submenus (RPM presets) ─────────────────────────────────
        // NOTE: a text field inside an NSMenu can't receive typed input (the menu's
        // modal event tracking swallows keystrokes), so per-fan control is a submenu
        // of plain menu items — those fire their actions reliably.
        // tag encodes (fan, rpm) as `fan * 100000 + rpm` (rpm < 100000, fan small).
        let rpmStep = Self.rpmStep
        for (i, f) in s.fans.enumerated() {
            let parent = NSMenuItem(title: Self.fanTitle(i, f), action: nil, keyEquivalent: "")
            let sub = NSMenu(title: "Quạt \(i + 1)")

            let autoItem = NSMenuItem(title: "Auto (hệ thống)", action: autoFan, keyEquivalent: "")
            autoItem.tag = i
            autoItem.target = target
            autoItem.state = f.forced ? .off : .on
            sub.addItem(autoItem)
            sub.addItem(.separator())

            // RPM steps from the first multiple of `rpmStep` ≥ min, up to (and incl.) max.
            var presetItems: [NSMenuItem] = []
            let lo = Int((f.min / Double(rpmStep)).rounded(.up)) * rpmStep
            let hi = Int(f.max)
            var rpm = Swift.max(lo, rpmStep)
            while rpm < hi {
                let item = NSMenuItem(title: "\(rpm) rpm", action: applyFanPreset, keyEquivalent: "")
                item.tag = i * 100000 + rpm
                item.target = target
                item.state = Self.presetState(f, presetRPM: rpm)
                sub.addItem(item)
                presetItems.append(item)
                rpm += rpmStep
            }
            if hi > 0 {
                let maxItem = NSMenuItem(title: "Max (\(hi) rpm)", action: applyFanPreset, keyEquivalent: "")
                maxItem.tag = i * 100000 + hi
                maxItem.target = target
                maxItem.state = Self.presetState(f, presetRPM: hi)
                sub.addItem(maxItem)
                presetItems.append(maxItem)
            }

            parent.submenu = sub
            menu.addItem(parent)
            liveFans.append(LiveFanItems(parent: parent, autoItem: autoItem, presetItems: presetItems))
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

        // ── 6. Process inspector ─────────────────────────────────────────────
        let processesItem = NSMenuItem(title: "Tiến trình...", action: showProcesses, keyEquivalent: "p")
        processesItem.target = target
        menu.addItem(processesItem)

        menu.addItem(.separator())

        // ── 7. Settings submenu ───────────────────────────────────────────────
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

        // ── 8. Separator ──────────────────────────────────────────────────────
        menu.addItem(.separator())

        // ── 9. Quit ───────────────────────────────────────────────────────────
        let quitItem = NSMenuItem(title: "Quit KuroTools", action: quit, keyEquivalent: "q")
        quitItem.target = target
        menu.addItem(quitItem)
    }
}
