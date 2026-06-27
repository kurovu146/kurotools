import Foundation

public enum SMCError: Error, Equatable {
    case driverNotFound
    case openFailed(kern_return_t)
    case keyNotFound(String)
    case readFailed(UInt8)
}

public final class SMC {
    public static let version = "0.1.0"
    let conn: SMCConnection

    public init() throws { conn = try SMCConnection() }

    /// Read key info (size + type).
    func keyInfo(_ key: SMCKey) throws -> (size: UInt32, type: UInt32) {
        var input = SMCParamStruct()
        input.key = key.fourCC
        input.data8 = SMCSelector.getKeyInfo.rawValue
        let out = try conn.call(&input)
        if out.result == 0x84 { throw SMCError.keyNotFound(key.string) }
        if out.result != 0 { throw SMCError.readFailed(out.result) }
        return (out.keyInfo.dataSize, out.keyInfo.dataType)
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
        if out.result != 0 { throw SMCError.readFailed(out.result) }
        let bytes = bytesToArray(out, count: Int(info.size))
        return SMCValue(key: key, dataType: SMCDataType(fourCC: info.type), bytes: bytes)
    }
}

// Re-export so `SMCKit.version` references in earlier test keep working.
public enum SMCKit { public static let version = SMC.version }

public extension SMC {
    /// Write raw bytes to an SMC key. Requires root on Apple Silicon.
    func write(_ key: SMCKey, bytes: [UInt8]) throws {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = key.fourCC
        input.keyInfo.dataSize = info.size
        input.keyInfo.dataType = info.type
        input.data8 = SMCSelector.writeKey.rawValue
        // copy bytes into the 32-byte tuple
        var tuple = input.bytes
        withUnsafeMutableBytes(of: &tuple) { dst in
            for (i, b) in bytes.prefix(Int(info.size)).enumerated() { dst[i] = b }
        }
        input.bytes = tuple
        let out = try conn.call(&input)
        if out.result == 0x84 { throw SMCError.keyNotFound(key.string) }
        if out.result != 0 { throw SMCError.readFailed(out.result) }
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
        let f = Float(rpm)
        let le = withUnsafeBytes(of: f) { Array($0) }   // little-endian on arm64
        try write(SMCKey("F0Tg"), bytes: le)
        try write(SMCKey("F1Tg"), bytes: le)
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
        if out.result != 0 { throw SMCError.readFailed(out.result) }
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
