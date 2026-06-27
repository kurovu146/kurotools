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
