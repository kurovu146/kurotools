import XCTest
@testable import SMCKit

final class SMCValueTests: XCTestCase {
    func testFloatDecode() {
        // 48.5 as little-endian IEEE-754 float = 0x42 0x41 0x00 0x00 (big-endian 0x42410000)
        var f: Float = 48.5
        let le = withUnsafeBytes(of: &f) { Array($0) } // host LE on arm64
        let v = SMCValue(key: SMCKey("Tp01"), dataType: .flt, bytes: le)
        XCTAssertEqual(v.double, 48.5, accuracy: 0.001)
    }

    func testFPE2Decode() {
        // fpe2: unsigned, 2 fractional bits. RPM 2400 -> raw 9600 = 0x2580, big-endian bytes [0x25,0x80]
        let v = SMCValue(key: SMCKey("F0Ac"), dataType: .fpe2, bytes: [0x25, 0x80])
        XCTAssertEqual(v.double, 2400, accuracy: 0.5)
    }

    func testUI16Decode() {
        // ui16 big-endian 0x0960 = 2400
        let v = SMCValue(key: SMCKey("F0Tg"), dataType: .ui16, bytes: [0x09, 0x60])
        XCTAssertEqual(v.double, 2400, accuracy: 0.5)
    }

    func testFourCCRoundTrip() {
        XCTAssertEqual(SMCKey("F0Ac").fourCC, 0x46304163)
    }

    func testFltBytesRoundTrip() {
        // Hermetic: SMC.fltBytes is a static func — no hardware connection needed.
        let bytes = SMC.fltBytes(2400)
        let decoded = SMCValue(key: SMCKey("F0Tg"), dataType: .flt, bytes: bytes).double
        XCTAssertEqual(decoded, 2400, accuracy: 0.5)
    }
}
