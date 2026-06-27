import Foundation

public struct SMCValue {
    public let key: SMCKey
    public let dataType: SMCDataType
    public let bytes: [UInt8]

    public init(key: SMCKey, dataType: SMCDataType, bytes: [UInt8]) {
        self.key = key
        self.dataType = dataType
        self.bytes = bytes
    }

    /// Decode raw SMC bytes into a Double per data type.
    public var double: Double {
        switch dataType {
        case .flt:
            guard bytes.count >= 4 else { return 0 }
            // SMC float bytes are little-endian on Apple Silicon.
            let bits = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8)
                     | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: bits))
        case .fpe2:
            guard bytes.count >= 2 else { return 0 }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw) / 4.0          // 2 fractional bits
        case .fp2e:
            guard bytes.count >= 2 else { return 0 }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw) / 16384.0      // 14 fractional bits
        case .ui16:
            guard bytes.count >= 2 else { return 0 }
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        case .ui32:
            guard bytes.count >= 4 else { return 0 }
            return Double((UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
                        | (UInt32(bytes[2]) << 8) | UInt32(bytes[3]))
        case .ui8:
            return Double(bytes.first ?? 0)
        case .si16:
            guard bytes.count >= 2 else { return 0 }
            return Double(Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1])))
        case .si8:
            return Double(Int8(bitPattern: bytes.first ?? 0))
        case .unknown:
            return 0
        }
    }
}
