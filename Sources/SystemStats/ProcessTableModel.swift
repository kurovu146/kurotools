import Foundation

public enum ProcessSortKey: String, Sendable {
    case name, pid, ports, cpu, memory
}

/// Row ordering for the process window.
///
/// Two rules keep the table usable while it auto-refreshes:
///  - every sort tie-breaks on PID, so the hundreds of idle 0.0% processes stop
///    shuffling on each sample (`Array.sort` is not stable);
///  - while a row is selected the order is frozen, so the row under the pointer
///    never slides away mid-click. Values still update in place.
public struct ProcessTableModel {
    public private(set) var rows: [RunningProcess] = []
    public var query: String = ""
    public var sortKey: ProcessSortKey = .cpu
    public var ascending: Bool = false

    /// PID of the selected row, or nil. Non-nil freezes the row order.
    public var selectedPID: Int32?

    private var source: [RunningProcess] = []

    public init() {}

    /// Takes a fresh sample, preserving the visible order while frozen.
    public mutating func refresh(with processes: [RunningProcess]) {
        source = processes
        rebuild(preservingOrder: selectedPID != nil)
    }

    /// Re-applies query and sort from scratch — for user-driven changes
    /// (typing in the search field, clicking a column header, deselecting).
    public mutating func rebuild() {
        rebuild(preservingOrder: false)
    }

    public func index(of pid: Int32) -> Int? {
        rows.firstIndex { $0.pid == pid }
    }

    private mutating func rebuild(preservingOrder: Bool) {
        let sorted = sort(filter(source))

        // Nothing to protect once the selected process is gone (killed, filtered
        // out) — resume live sorting rather than freezing on a stale order.
        guard preservingOrder,
              let selectedPID,
              sorted.contains(where: { $0.pid == selectedPID }) else {
            rows = sorted
            return
        }

        let bySortedIndex = Dictionary(sorted.enumerated().map { ($0.element.pid, $0.offset) },
                                       uniquingKeysWith: { first, _ in first })
        var kept: [RunningProcess] = []
        var keptPIDs = Set<Int32>()
        kept.reserveCapacity(sorted.count)

        for row in rows {
            guard let index = bySortedIndex[row.pid], keptPIDs.insert(row.pid).inserted else { continue }
            kept.append(sorted[index])
        }
        rows = kept + sorted.filter { !keptPIDs.contains($0.pid) }
    }

    private func filter(_ processes: [RunningProcess]) -> [RunningProcess] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return processes }

        return processes.filter { process in
            process.name.localizedCaseInsensitiveContains(trimmed)
                || process.command.localizedCaseInsensitiveContains(trimmed)
                || String(process.pid).contains(trimmed)
                || process.ports.contains { String($0).contains(trimmed) }
        }
    }

    private func sort(_ processes: [RunningProcess]) -> [RunningProcess] {
        processes.sorted { lhs, rhs in
            switch sortKey {
            case .name:
                let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if order != .orderedSame { return ascending == (order == .orderedAscending) }
            case .pid:
                break
            case .ports:
                let l = lhs.ports.first ?? Int.max
                let r = rhs.ports.first ?? Int.max
                if l != r { return ascending == (l < r) }
            case .cpu:
                if lhs.cpuPercent != rhs.cpuPercent { return ascending == (lhs.cpuPercent < rhs.cpuPercent) }
            case .memory:
                if lhs.residentMemoryBytes != rhs.residentMemoryBytes {
                    return ascending == (lhs.residentMemoryBytes < rhs.residentMemoryBytes)
                }
            }
            // PID is unique, so this makes the whole ordering deterministic.
            return sortKey == .pid ? ascending == (lhs.pid < rhs.pid) : lhs.pid < rhs.pid
        }
    }
}
