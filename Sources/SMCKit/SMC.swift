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
