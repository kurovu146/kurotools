import XCTest
@testable import SystemStats

final class ProcessSamplerTests: XCTestCase {
    func testParsePSProcessLine() throws {
        let process = try XCTUnwrap(parsePSProcessLine("  1234   12.5  204800 /Applications/Foo Bar.app/Contents/MacOS/Foo Bar"))

        XCTAssertEqual(process.pid, 1234)
        XCTAssertEqual(process.cpuPercent, 12.5, accuracy: 0.001)
        XCTAssertEqual(process.residentMemoryBytes, 204800 * 1_024)
        XCTAssertEqual(process.command, "/Applications/Foo Bar.app/Contents/MacOS/Foo Bar")
        XCTAssertEqual(process.name, "Foo Bar")
        XCTAssertEqual(process.ports, [])
    }

    func testParsePSProcessLineRejectsMalformedRows() {
        XCTAssertNil(parsePSProcessLine(""))
        XCTAssertNil(parsePSProcessLine("PID CPU RSS COMMAND"))
        XCTAssertNil(parsePSProcessLine("abc 1.0 100 /bin/example"))
        XCTAssertNil(parsePSProcessLine("123 abc 100 /bin/example"))
        XCTAssertNil(parsePSProcessLine("123 1.0 abc /bin/example"))
    }

    func testProcessNameFallsBackForPlainCommands() {
        XCTAssertEqual(processName(fromCommand: "launchd"), "launchd")
        XCTAssertEqual(processName(fromCommand: "   "), "(unknown)")
    }

    func testParseLsofPortOutputGroupsPortsByPID() {
        let output = """
        p1119
        f9
        PTCP
        n*:7000
        f10
        PTCP
        n*:7000
        f11
        PTCP
        n127.0.0.1:5000
        p2222
        f7
        PTCP
        n[::1]:5432
        f8
        PUDP
        n*:*
        """

        let ports = parseLsofPortOutput(output)

        XCTAssertEqual(ports[1119], [5000, 7000])
        XCTAssertEqual(ports[2222], [5432])
    }

    func testParsePortFromLsofName() {
        XCTAssertEqual(parsePort(fromLsofName: "*:3000"), 3000)
        XCTAssertEqual(parsePort(fromLsofName: "127.0.0.1:9000"), 9000)
        XCTAssertEqual(parsePort(fromLsofName: "[::1]:5432"), 5432)
        XCTAssertNil(parsePort(fromLsofName: "*:*"))
        XCTAssertNil(parsePort(fromLsofName: "no-port"))
    }
}
