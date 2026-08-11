import XCTest
@testable import SystemStats

final class ProcessTableModelTests: XCTestCase {
    private func process(_ pid: Int32,
                         name: String = "proc",
                         cpu: Double = 0,
                         rssMB: UInt64 = 1,
                         ports: [Int] = []) -> RunningProcess {
        RunningProcess(
            pid: pid,
            name: name,
            command: "/usr/bin/\(name)",
            cpuPercent: cpu,
            residentMemoryBytes: rssMB * 1_048_576,
            ports: ports
        )
    }

    // MARK: - Stable ordering

    func testEqualValuesTieBreakOnPIDSoOrderNeverChurns() {
        var model = ProcessTableModel()
        let idle = [process(300), process(100), process(200)]

        model.refresh(with: idle)
        let first = model.rows.map(\.pid)

        // Same processes, different arrival order from ps — order must not move.
        model.refresh(with: [process(200), process(300), process(100)])

        XCTAssertEqual(first, [100, 200, 300])
        XCTAssertEqual(model.rows.map(\.pid), first)
    }

    // MARK: - Frozen order while a row is selected

    func testOrderFreezesWhileRowSelected() {
        var model = ProcessTableModel()
        model.refresh(with: [process(1, cpu: 90), process(2, cpu: 50), process(3, cpu: 10)])
        XCTAssertEqual(model.rows.map(\.pid), [1, 2, 3])

        model.selectedPID = 3

        // CPU flips completely; the visible order must stay put.
        model.refresh(with: [process(1, cpu: 5), process(2, cpu: 80), process(3, cpu: 99)])

        XCTAssertEqual(model.rows.map(\.pid), [1, 2, 3])
        XCTAssertEqual(model.rows[2].cpuPercent, 99, accuracy: 0.001, "values still update in place")
    }

    func testNewProcessesAppendAtEndWhileFrozen() {
        var model = ProcessTableModel()
        model.refresh(with: [process(1, cpu: 90), process(2, cpu: 50)])
        model.selectedPID = 2

        model.refresh(with: [process(1, cpu: 90), process(2, cpu: 50), process(9, cpu: 99)])

        XCTAssertEqual(model.rows.map(\.pid), [1, 2, 9], "a busy newcomer must not push the selection down")
    }

    func testGoneProcessesDropOutWhileFrozen() {
        var model = ProcessTableModel()
        model.refresh(with: [process(1, cpu: 90), process(2, cpu: 50), process(3, cpu: 10)])
        model.selectedPID = 3

        model.refresh(with: [process(1, cpu: 90), process(3, cpu: 10)])

        XCTAssertEqual(model.rows.map(\.pid), [1, 3])
    }

    func testOrderResumesSortingWhenSelectionCleared() {
        var model = ProcessTableModel()
        model.refresh(with: [process(1, cpu: 90), process(2, cpu: 50)])
        model.selectedPID = 1
        model.refresh(with: [process(1, cpu: 1), process(2, cpu: 99)])
        XCTAssertEqual(model.rows.map(\.pid), [1, 2])

        model.selectedPID = nil
        model.rebuild()

        XCTAssertEqual(model.rows.map(\.pid), [2, 1])
    }

    func testUnfreezesWhenSelectedProcessDisappears() {
        var model = ProcessTableModel()
        model.refresh(with: [process(1, cpu: 90), process(2, cpu: 50)])
        model.selectedPID = 1

        // PID 1 was killed — nothing left to protect, so sort freely again.
        model.refresh(with: [process(2, cpu: 50), process(3, cpu: 99)])

        XCTAssertEqual(model.rows.map(\.pid), [3, 2])
    }

    // MARK: - Selection tracking

    func testIndexOfPIDFollowsProcessAcrossReorder() {
        var model = ProcessTableModel()
        model.refresh(with: [process(1, cpu: 90), process(2, cpu: 50), process(3, cpu: 10)])
        XCTAssertEqual(model.index(of: 3), 2)

        model.refresh(with: [process(1, cpu: 1), process(2, cpu: 2), process(3, cpu: 99)])

        XCTAssertEqual(model.index(of: 3), 0, "selection must follow the PID, not the row index")
        XCTAssertNil(model.index(of: 404))
    }

    // MARK: - Filtering

    func testQueryMatchesNamePIDPortAndCommand() {
        var model = ProcessTableModel()
        model.refresh(with: [
            process(101, name: "node", ports: [3000]),
            process(202, name: "Xcode"),
            process(303, name: "postgres", ports: [5432]),
        ])

        model.query = "3000"
        model.rebuild()
        XCTAssertEqual(model.rows.map(\.pid), [101])

        model.query = "xcode"
        model.rebuild()
        XCTAssertEqual(model.rows.map(\.pid), [202], "name match is case-insensitive")

        model.query = "202"
        model.rebuild()
        XCTAssertEqual(model.rows.map(\.pid), [202])

        model.query = "/usr/bin/postgres"
        model.rebuild()
        XCTAssertEqual(model.rows.map(\.pid), [303])
    }

    func testQueryStillFiltersWhileFrozen() {
        var model = ProcessTableModel()
        model.query = "node"
        model.refresh(with: [process(1, name: "node"), process(2, name: "Xcode")])
        model.selectedPID = 1

        model.refresh(with: [process(1, name: "node"), process(2, name: "Xcode"), process(3, name: "nodemon")])

        XCTAssertEqual(model.rows.map(\.pid), [1, 3], "freezing order must not bypass the search filter")
    }

    // MARK: - Sort keys

    func testSortKeysCoverEveryColumn() {
        var model = ProcessTableModel()
        let sample = [
            process(2, name: "bravo", cpu: 5, rssMB: 300, ports: [8080]),
            process(1, name: "alpha", cpu: 9, rssMB: 100, ports: [80]),
            process(3, name: "Charlie", cpu: 1, rssMB: 200, ports: []),
        ]
        model.refresh(with: sample)

        model.sortKey = .name
        model.ascending = true
        model.rebuild()
        XCTAssertEqual(model.rows.map(\.name), ["alpha", "bravo", "Charlie"])

        model.sortKey = .pid
        model.rebuild()
        XCTAssertEqual(model.rows.map(\.pid), [1, 2, 3])

        model.sortKey = .memory
        model.ascending = false
        model.rebuild()
        XCTAssertEqual(model.rows.map(\.pid), [2, 3, 1])

        model.sortKey = .ports
        model.ascending = true
        model.rebuild()
        XCTAssertEqual(model.rows.map(\.pid), [1, 2, 3], "port-less processes sort last")
    }
}
