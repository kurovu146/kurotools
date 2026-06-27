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
    public static func load() -> Settings {
        var s = Settings()
        if d.object(forKey: "showTemp") != nil { s.showTemp = d.bool(forKey: "showTemp") }
        if d.object(forKey: "showCPU") != nil { s.showCPU = d.bool(forKey: "showCPU") }
        if d.object(forKey: "showRAM") != nil { s.showRAM = d.bool(forKey: "showRAM") }
        if d.object(forKey: "showFan") != nil { s.showFan = d.bool(forKey: "showFan") }
        if d.object(forKey: "thresholdC") != nil { s.thresholdC = d.double(forKey: "thresholdC") }
        if d.object(forKey: "refreshSeconds") != nil { s.refreshSeconds = d.double(forKey: "refreshSeconds") }
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
