import Foundation

public protocol SMCReading {
    func read(_ key: SMCKey) throws -> SMCValue
    func allKeys() throws -> [SMCKey]
}

public extension SMCReading {
    /// Những quạt THẬT SỰ điều khiển được, kèm trần RPM đã đọc sẵn.
    ///
    /// Một quạt tự chứng minh bằng đúng một điều kiện: `F{i}Mx` đọc được và lớn
    /// hơn 0. Trần RPM là thứ duy nhất khiến quạt có nghĩa — không có nó thì
    /// không dựng được preset nào và "Max" nghĩa là 0 vòng/phút.
    ///
    /// Không hỏi `fanCount()` làm nguồn sự thật vì FNum nói dối theo hai hướng:
    /// đọc lỗi thì nó khai 1 (máy không quạt hiện ra "Quạt 1: 0 rpm" với dải
    /// preset 0..0), còn khai thừa thì fan không tồn tại vẫn đọc ra 0 vì `try?`
    /// biến `keyNotFound` thành nil rồi thành 0. FNum chỉ còn nói nên thử tới
    /// đâu; đọc lỗi thì thử hết `maxProbe` để máy có quạt mà FNum hỏng vẫn dùng được.
    ///
    /// Trả kèm `maxRPM` để bên gọi khỏi đọc lại chính key vừa đọc — mỗi lần đọc
    /// là một lệnh gọi IOKit.
    func controllableFans(maxProbe: Int = 8) -> [(index: Int, maxRPM: Double)] {
        let hinted = Int((try? read(SMCKey("FNum")))?.double ?? 0)
        let probe = (hinted > 0 && hinted <= maxProbe) ? hinted : maxProbe
        return (0..<probe).compactMap { i in
            let max = (try? read(SMCKey("F\(i)Mx")))?.double ?? 0
            return max > 0 ? (index: i, maxRPM: max) : nil
        }
    }
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

    /// Number of fans (SMC key "FNum", ui8). Clamped to 1...8; defaults to 1 on failure.
    ///
    /// ⚠️ Đây là LỜI KHAI của SMC, không phải sự thật đã kiểm chứng: nó mặc định
    /// về 1 khi FNum đọc lỗi, nên trên máy không quạt nó vẫn khai có một cái.
    /// Thứ quyết định có hiện điều khiển quạt hay không là `controllableFans()`.
    func fanCount() -> Int {
        let n = Int((try? read(SMCKey("FNum")))?.double ?? 1)
        return Swift.min(Swift.max(n, 1), 8)
    }


    /// F{fan}Md (ui8): 1 = forced/manual, 0 = auto.
    func setFanMode(fan: Int, forced: Bool) throws {
        try write(SMCKey("F\(fan)Md"), bytes: [forced ? 1 : 0])
    }

    /// F{fan}Tg (flt, little-endian) target RPM.
    func setFanTarget(fan: Int, rpm: Double) throws {
        try write(SMCKey("F\(fan)Tg"), bytes: SMC.fltBytes(rpm))
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
