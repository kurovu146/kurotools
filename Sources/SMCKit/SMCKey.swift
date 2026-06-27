import Foundation

public struct SMCKey: Equatable, CustomStringConvertible {
    public let fourCC: UInt32
    public let string: String

    public init(_ string: String) {
        precondition(string.utf8.count == 4, "SMC key must be 4 ASCII chars")
        var code: UInt32 = 0
        for b in string.utf8 { code = (code << 8) | UInt32(b) }
        self.fourCC = code
        self.string = string
    }

    public init(fourCC: UInt32) {
        self.fourCC = fourCC
        let chars = [UInt8((fourCC >> 24) & 0xff), UInt8((fourCC >> 16) & 0xff),
                     UInt8((fourCC >> 8) & 0xff), UInt8(fourCC & 0xff)]
        self.string = String(bytes: chars, encoding: .ascii) ?? "?"
    }

    public var description: String { string }
}

public enum SMCDataType: String {
    case flt  = "flt "
    case fpe2 = "fpe2"
    case fp2e = "fp2e"
    case ui8  = "ui8 "
    case ui16 = "ui16"
    case ui32 = "ui32"
    case si8  = "si8 "
    case si16 = "si16"
    case unknown = "????"

    public init(fourCC: UInt32) {
        self = SMCDataType(rawValue: SMCKey(fourCC: fourCC).string) ?? .unknown
    }
}
