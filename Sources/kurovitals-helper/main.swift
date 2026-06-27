import Foundation
import SMCKit
import HelperProtocol

// Single-threaded accept loop + a 1 Hz watchdog timer on a background queue.
final class Daemon {
    let smc: SMC
    var deadline: Date?          // when the current manual-mode window expires
    let lock = NSLock()

    init() throws { smc = try SMC() }

    func handle(_ cmd: FanCommand) -> FanResponse {
        switch cmd {
        case .ping:
            return FanResponse(ok: true, message: "pong")

        case .setAuto:
            do {
                try smc.setFanMode(false)
                lock.lock(); deadline = nil; lock.unlock()
                return FanResponse(ok: true, message: "auto")
            } catch {
                return FanResponse(ok: false, message: "\(error)")
            }

        case let .setTarget(rpm, ttl):
            // Validate strictly — this daemon runs as root.
            guard rpm > 0, rpm < 12000, ttl >= 1, ttl <= 60 else {
                return FanResponse(ok: false, message: "invalid args: rpm must be 1..<12000, ttl must be 1...60")
            }
            do {
                try smc.setFanMode(true)
                try smc.setFanTarget(rpm: Double(rpm))
                lock.lock()
                deadline = Date().addingTimeInterval(TimeInterval(ttl))
                lock.unlock()
                return FanResponse(ok: true, message: "target \(rpm)")
            } catch {
                return FanResponse(ok: false, message: "\(error)")
            }
        }
    }

    func watchdogTick() {
        lock.lock(); let d = deadline; lock.unlock()
        if let d = d, Date() > d {
            try? smc.setFanMode(false)
            lock.lock(); deadline = nil; lock.unlock()
            FileHandle.standardError.write(
                Data("watchdog: reverted to Auto\n".utf8)
            )
        }
    }
}

// Create, bind, chmod, and listen on a Unix-domain socket.
// Returns the listening file descriptor.
func makeSocket(path: String) -> Int32 {
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = path.utf8CString
    withUnsafeMutablePointer(to: &addr.sun_path) {
        $0.withMemoryRebound(to: CChar.self, capacity: bytes.count) { dst in
            bytes.withUnsafeBufferPointer {
                dst.update(from: $0.baseAddress!, count: bytes.count)
            }
        }
    }
    _ = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    // Allow the console user to connect (single-user machine).
    chmod(path, 0o666)
    listen(fd, 8)
    return fd
}

// ── Setup ────────────────────────────────────────────────────────────────────

// Socket path: overridable via env var for smoke-testing without root.
let socketPath = ProcessInfo.processInfo.environment["KUROVITALS_SOCKET"] ?? kHelperSocketPath

let daemon = try Daemon()
let listenFD = makeSocket(path: socketPath)

// ── Watchdog timer (1 Hz on background queue) ────────────────────────────────

let watchdogQueue = DispatchQueue(label: "com.kurovitals.watchdog")
let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
timer.schedule(deadline: .now() + 1, repeating: 1.0)
timer.setEventHandler { daemon.watchdogTick() }
timer.resume()

// ── Signal handlers (via DispatchSource — safe to call Swift code) ────────────

// Mask the signals so the default handler doesn't fire before DispatchSource picks them up.
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)

let sigtermSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: watchdogQueue)
sigtermSrc.setEventHandler {
    try? daemon.smc.setFanMode(false)
    exit(0)
}
sigtermSrc.resume()

let sigintSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: watchdogQueue)
sigintSrc.setEventHandler {
    try? daemon.smc.setFanMode(false)
    exit(0)
}
sigintSrc.resume()

// ── Accept loop (blocks main thread) ─────────────────────────────────────────

while true {
    let clientFD = accept(listenFD, nil, nil)
    if clientFD < 0 { continue }
    defer { close(clientFD) }

    var buf = [UInt8](repeating: 0, count: 1024)
    let n = read(clientFD, &buf, buf.count)
    guard n > 0 else { continue }

    // Decode the first newline-delimited JSON line.
    let received = Data(buf[0..<n])
    let lineData: Data
    if let idx = received.firstIndex(of: 0x0A) {
        lineData = Data(received[received.startIndex..<idx])
    } else {
        lineData = received
    }

    let resp: FanResponse
    if let cmd = try? JSONDecoder().decode(FanCommand.self, from: lineData) {
        resp = daemon.handle(cmd)
    } else {
        resp = FanResponse(ok: false, message: "bad request")
    }

    if var out = try? JSONEncoder().encode(resp) {
        out.append(0x0A)   // newline delimiter
        _ = out.withUnsafeBytes { write(clientFD, $0.baseAddress, out.count) }
    }
}
