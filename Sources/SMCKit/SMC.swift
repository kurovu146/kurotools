import Foundation

public protocol SMCReading {
    func read(_ key: SMCKey) throws -> SMCValue
    func allKeys() throws -> [SMCKey]
}

public enum SMCError: Error, Equatable {
    case driverNotFound
    case openFailed(kern_return_t)
    case keyNotFound(String)
    case operationFailed(UInt8)       // thrown from read AND write (was readFailed)
    case callFailed(kern_return_t)    // Mach call failed with non-success kr
}

public final class SMC {
    public static let version = "0.1.0"
    let conn: SMCConnection
    // SMC is used single-threaded from the main timer; no lock needed.
    private var infoCache: [UInt32: (size: UInt32, type: UInt32)] = [:]

    public init() throws { conn = try SMCConnection() }

    /// Read key info (size + type). SMC key size/type are static for a boot session.
    func keyInfo(_ key: SMCKey) throws -> (size: UInt32, type: UInt32) {
        if let hit = infoCache[key.fourCC] { return hit }
        var input = SMCParamStruct()
        input.key = key.fourCC
        input.data8 = SMCSelector.getKeyInfo.rawValue
        let out = try conn.call(&input)
        if out.result == 0x84 { throw SMCError.keyNotFound(key.string) }
        if out.result != 0 { throw SMCError.operationFailed(out.result) }
        let info = (out.keyInfo.dataSize, out.keyInfo.dataType)
        infoCache[key.fourCC] = info
        return info
    }

    public func read(_ key: SMCKey) throws -> SMCValue {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = key.fourCC
        input.keyInfo.dataSize = info.size
        input.keyInfo.dataType = info.type
        input.data8 = SMCSelector.readKey.rawValue
        let out = try conn.call(&input)
        if out.result == 0x84 { throw SMCError.keyNotFound(key.string) }
        if out.result != 0 { throw SMCError.operationFailed(out.result) }
        let bytes = bytesToArray(out, count: Int(info.size))
        return SMCValue(key: key, dataType: SMCDataType(fourCC: info.type), bytes: bytes)
    }
}

extension SMC: SMCReading {}

public extension SMC {
    /// Encode a Double as little-endian IEEE-754 float bytes (no SMC connection needed).
    static func fltBytes(_ value: Double) -> [UInt8] {
        withUnsafeBytes(of: Float(value)) { Array($0) }
    }

    /// Write raw bytes to an SMC key. Requires root on Apple Silicon.
    func write(_ key: SMCKey, bytes: [UInt8]) throws {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = key.fourCC
        input.keyInfo.dataSize = info.size
        input.keyInfo.dataType = info.type
        input.data8 = SMCSelector.writeKey.rawValue
        withUnsafeMutableBytes(of: &input.bytes) { dst in
            for (i, b) in bytes.prefix(Int(info.size)).enumerated() { dst[i] = b }
        }
        let out = try conn.call(&input)
        if out.result == 0x84 { throw SMCError.keyNotFound(key.string) }
        if out.result != 0 { throw SMCError.operationFailed(out.result) }
    }

    /// Set fan mode for both fans. forced=true → manual speed control; false → auto.
    /// F0Md / F1Md are ui8: 1 = forced, 0 = auto.
    func setFanMode(_ forced: Bool) throws {
        let byte: UInt8 = forced ? 1 : 0
        try write(SMCKey("F0Md"), bytes: [byte])
        try write(SMCKey("F1Md"), bytes: [byte])
    }

    /// Set target RPM for both fans. F0Tg / F1Tg are type `flt` (4-byte IEEE 754, little-endian).
    /// On M2 Pro: min ≈ 2317 RPM, max = 6800 RPM.
    func setFanTarget(rpm: Double) throws {
        try write(SMCKey("F0Tg"), bytes: SMC.fltBytes(rpm))
        try write(SMCKey("F1Tg"), bytes: SMC.fltBytes(rpm))
    }
}

public extension SMC {
    func keyCount() throws -> Int {
        let v = try read(SMCKey("#KEY"))   // ui32 count of keys
        return Int(v.double)
    }

    func key(atIndex index: Int) throws -> SMCKey {
        var input = SMCParamStruct()
        input.data8 = SMCSelector.getKeyFromIndex.rawValue
        input.data32 = UInt32(index)
        let out = try conn.call(&input)
        if out.result != 0 { throw SMCError.operationFailed(out.result) }
        return SMCKey(fourCC: out.key)
    }

    func allKeys() throws -> [SMCKey] {
        let n = try keyCount()
        var keys: [SMCKey] = []
        keys.reserveCapacity(n)
        for i in 0..<n { keys.append(try key(atIndex: i)) }
        return keys
    }
}
