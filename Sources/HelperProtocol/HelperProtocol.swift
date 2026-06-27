import Foundation

public let kHelperSocketPath = "/var/run/kurovitals.sock"

public enum FanCommand: Codable, Equatable {
    case setTarget(fan: Int, rpm: Int, ttlSeconds: Int)
    case setAuto(fan: Int)
    case allAuto                 // revert ALL fans (quit / over-temp / safety)
    case ping
}

public struct FanResponse: Codable, Equatable {
    public let ok: Bool
    public let message: String
    public init(ok: Bool, message: String) { self.ok = ok; self.message = message }
}
