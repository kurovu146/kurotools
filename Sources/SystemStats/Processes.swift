import Darwin
import Foundation

public struct RunningProcess: Equatable {
    public let pid: Int32
    public let name: String
    public let command: String
    public let cpuPercent: Double
    public let residentMemoryBytes: UInt64
    public let ports: [Int]

    public init(pid: Int32, name: String, command: String, cpuPercent: Double, residentMemoryBytes: UInt64, ports: [Int] = []) {
        self.pid = pid
        self.name = name
        self.command = command
        self.cpuPercent = cpuPercent
        self.residentMemoryBytes = residentMemoryBytes
        self.ports = ports
    }

    public var residentMemoryMB: Double {
        Double(residentMemoryBytes) / 1_048_576.0
    }
}

public enum ProcessSamplerError: Error, LocalizedError {
    case psFailed(Int32)
    case invalidOutput

    public var errorDescription: String? {
        switch self {
        case .psFailed(let code): return "ps exited with status \(code)"
        case .invalidOutput: return "ps returned invalid UTF-8 output"
        }
    }
}

public enum ProcessKillError: Error, LocalizedError {
    case invalidPID(Int32)
    case posix(POSIXErrorCode)

    public var errorDescription: String? {
        switch self {
        case .invalidPID(let pid): return "Invalid process id \(pid)"
        case .posix(let code): return String(cString: strerror(code.rawValue))
        }
    }
}

/// Not thread-safe: the port cache means one instance belongs to one serial queue.
public final class ProcessSampler: @unchecked Sendable {
    private var cachedPorts: [Int32: [Int]] = [:]

    public init() {}

    /// - Parameter refreshPorts: `lsof` costs a few hundred ms and listening
    ///   ports rarely change, so callers polling on a timer can reuse the last
    ///   scan for a few ticks. Row order is decided by `ProcessTableModel`.
    public func listProcesses(refreshPorts: Bool = true) throws -> [RunningProcess] {
        if refreshPorts {
            cachedPorts = openPortsByPID()
        }
        let portsByPID = cachedPorts

        return try listBaseProcesses().map { process in
            RunningProcess(
                pid: process.pid,
                name: process.name,
                command: process.command,
                cpuPercent: process.cpuPercent,
                residentMemoryBytes: process.residentMemoryBytes,
                ports: portsByPID[process.pid] ?? []
            )
        }
    }

    private func listBaseProcesses() throws -> [RunningProcess] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,pcpu=,rss=,comm="]

        let output = Pipe()
        let error = Pipe()
        task.standardOutput = output
        task.standardError = error

        try task.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        _ = error.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw ProcessSamplerError.psFailed(task.terminationStatus)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProcessSamplerError.invalidOutput
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parsePSProcessLine(String($0)) }
    }

    private func openPortsByPID() -> [Int32: [Int]] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-iUDP", "-F", "pPn"]

        let output = Pipe()
        let error = Pipe()
        task.standardOutput = output
        task.standardError = error

        do {
            try task.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            _ = error.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            guard task.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else {
                return [:]
            }
            return parseLsofPortOutput(text)
        } catch {
            return [:]
        }
    }
}

public func terminateProcess(pid: Int32, signal: Int32 = SIGTERM) throws {
    guard pid > 0 else { throw ProcessKillError.invalidPID(pid) }
    guard Darwin.kill(pid, signal) == 0 else {
        let code = POSIXErrorCode(rawValue: errno) ?? .EPERM
        throw ProcessKillError.posix(code)
    }
}

func parsePSProcessLine(_ line: String) -> RunningProcess? {
    let parts = line
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(maxSplits: 3, omittingEmptySubsequences: true) { $0.isWhitespace }

    guard parts.count == 4,
          let pid = Int32(parts[0]),
          let cpu = Double(parts[1]),
          let rssKB = UInt64(parts[2]) else {
        return nil
    }

    let command = String(parts[3])
    return RunningProcess(
        pid: pid,
        name: processName(fromCommand: command),
        command: command,
        cpuPercent: cpu,
        residentMemoryBytes: rssKB * 1_024
    )
}

func processName(fromCommand command: String) -> String {
    let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "(unknown)" }
    return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
}

func parseLsofPortOutput(_ text: String) -> [Int32: [Int]] {
    var currentPID: Int32?
    var portsByPID: [Int32: Set<Int>] = [:]

    for line in text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
        guard let field = line.first else { continue }
        let value = String(line.dropFirst())

        switch field {
        case "p":
            currentPID = Int32(value)
        case "n":
            guard let pid = currentPID, let port = parsePort(fromLsofName: value) else { continue }
            portsByPID[pid, default: []].insert(port)
        default:
            continue
        }
    }

    return portsByPID.mapValues { $0.sorted() }
}

func parsePort(fromLsofName name: String) -> Int? {
    guard let colon = name.lastIndex(of: ":") else { return nil }
    let tail = name[name.index(after: colon)...]
    let digits = tail.prefix { $0.isNumber }
    guard !digits.isEmpty, let port = Int(digits), port > 0 else { return nil }
    return port
}
