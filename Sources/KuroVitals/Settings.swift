import Foundation

public struct Settings {
    public var showTemp = true
    public var showCPU = true
    public var showRAM = true
    public var showFan = true
    public var thresholdC: Double = 95
    public var refreshSeconds: Double = 1.5
    public init() {}

    private static let d = UserDefaults.standard
    private static let defaultValues: [String: Any] = [
        "showTemp": true, "showCPU": true, "showRAM": true, "showFan": true,
        "thresholdC": 95.0, "refreshSeconds": 1.5,
    ]
    public static func load() -> Settings {
        d.register(defaults: defaultValues)
        var s = Settings()
        s.showTemp = d.bool(forKey: "showTemp"); s.showCPU = d.bool(forKey: "showCPU")
        s.showRAM = d.bool(forKey: "showRAM");   s.showFan = d.bool(forKey: "showFan")
        s.thresholdC = d.double(forKey: "thresholdC"); s.refreshSeconds = d.double(forKey: "refreshSeconds")
        return s
    }
    public func save() {
        Settings.d.set(showTemp, forKey: "showTemp")
        Settings.d.set(showCPU, forKey: "showCPU")
        Settings.d.set(showRAM, forKey: "showRAM")
        Settings.d.set(showFan, forKey: "showFan")
        Settings.d.set(thresholdC, forKey: "thresholdC")
        Settings.d.set(refreshSeconds, forKey: "refreshSeconds")
    }
}
