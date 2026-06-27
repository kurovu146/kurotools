import Foundation
import HelperProtocol

public final class HelperClient: FanCommanding {
    private let socketPath: String
    public init(socketPath: String = kHelperSocketPath) { self.socketPath = socketPath }

    public func send(_ command: FanCommand) -> FanResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return FanResponse(ok: false, message: "socket() failed") }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            return FanResponse(ok: false, message: "socket path too long")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                pathBytes.withUnsafeBufferPointer { src in
                    dst.update(from: src.baseAddress!, count: pathBytes.count)
                }
            }
        }
        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            return FanResponse(ok: false, message: "helper not running")
        }
        guard var data = try? JSONEncoder().encode(command) else {
            return FanResponse(ok: false, message: "encode failed")
        }
        data.append(0x0A) // newline delimiter
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }

        var buf = [UInt8](repeating: 0, count: 1024)
        let n = read(fd, &buf, buf.count)
        guard n > 0 else { return FanResponse(ok: false, message: "no/invalid response") }
        // Split on newline using [UInt8] to avoid Data Sequence/Collection ambiguity
        let received: [UInt8] = Array(buf[0..<n])
        let lineBytes = received.split(separator: UInt8(0x0A)).first.map(Array.init) ?? received
        guard let resp = try? JSONDecoder().decode(FanResponse.self, from: Data(lineBytes))
        else { return FanResponse(ok: false, message: "no/invalid response") }
        return resp
    }
}
