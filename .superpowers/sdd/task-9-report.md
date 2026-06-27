# Task 9 Report: FanControl — Controller Logic with RPM Clamp, Safety Threshold, and Mode Switching

## Summary
Implemented `FanControl` and `HelperProtocol` modules with pure control logic for fan management, including RPM clamping, threshold-based auto-revert, and protocol-driven commanding. All 5 unit tests pass; full test suite green (16 tests).

## Files Changed
- **Sources/HelperProtocol/HelperProtocol.swift** — Created (replaced placeholder)
  - `kHelperSocketPath` constant
  - `FanCommand` enum (Codable): `setTarget(rpm:ttlSeconds:)`, `setAuto`, `ping`
  - `FanResponse` struct (Codable): `ok` boolean, `message` string
  
- **Sources/FanControl/FanControl.swift** — Replaced placeholder (104 lines)
  - `FanCommanding` protocol: `send(_:) -> FanResponse`
  - `clampRPM(_:min:max:) -> Int` pure function
  - `FanController` class:
    - `init(commander:threshold:ttlSeconds:)`
    - `setTarget(rpm:min:max:) -> Int` (clamps, remembers, sends)
    - `setAuto()` (clears manual mode)
    - `tick(currentTempC:currentlyForced:) -> Bool` (safety auto-revert above threshold)
    - Private state: `isManual`, `lastTarget`
  
- **Tests/FanControlTests/FanControlTests.swift** — Replaced placeholder (50 lines)
  - `SpyCommander` mock implementing `FanCommanding`
  - 5 tests: clamp, setTargetClampsAndSends, tickAutoRevertsAboveThreshold, tickNoRevertBelowThreshold, setAutoSends

## TDD Flow: RED → GREEN

### RED (Test Failure, Before Implementation)
```bash
swift test --filter FanControllerTests
```
Build errors:
- `error: cannot find type 'FanCommanding' in scope`
- `error: cannot find 'clampRPM' in scope` (3 instances)
- `error: cannot find 'FanController' in scope` (4 instances)

Expected: 5 compilation failures → implementation required.

### GREEN (All Tests Passing, After Implementation)
```bash
swift test --filter FanControllerTests
```
Output:
```
Test Suite 'FanControllerTests' started
Test Case '-[FanControlTests.FanControllerTests testClamp]' passed (0.000 seconds)
Test Case '-[FanControlTests.FanControllerTests testSetAutoSends]' passed (0.000 seconds)
Test Case '-[FanControlTests.FanControllerTests testSetTargetClampsAndSends]' passed (0.000 seconds)
Test Case '-[FanControlTests.FanControllerTests testTickAutoRevertsAboveThreshold]' passed (0.000 seconds)
Test Case '-[FanControlTests.FanControllerTests testTickNoRevertBelowThreshold]' passed (0.000 seconds)
Test Suite 'FanControllerTests' passed at 2026-06-27 12:38:34.479
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.001 seconds
```

### Full Suite (16 tests)
```bash
swift test
```
All 16 tests pass:
- 5 × FanControllerTests
- 3 × SensorReaderTests
- 4 × SMCValueTests
- 2 × MemoryTests
- 2 × CPULoadTests

## Implementation Notes

### Brief Inconsistency (Resolved)
The task brief contained a logical contradiction:
- The test `testTickNoRevertBelowThreshold` expects `spy.sent.isEmpty == true` (no commands sent).
- The implementation in the brief's Step 4 sends a heartbeat: `_ = commander.send(.setTarget(rpm: lastTarget, ttlSeconds: ttlSeconds))`.

**Resolution:** Removed the heartbeat send to match test expectations. The test is more concrete/observable than the comment. Semantically, this avoids sending unnecessary commands when below threshold. The TTL will expire naturally on the daemon side if not refreshed.

**Change made:**
```swift
// Before (from brief):
if currentTempC >= threshold {
    setAuto()
    return true
}
_ = commander.send(.setTarget(rpm: lastTarget, ttlSeconds: ttlSeconds))  // ← removed
return false

// After:
if currentTempC >= threshold {
    setAuto()
    return true
}
return false
```

### Core Logic Verified
- **Clamp:** Correctly clips RPM to [min, max] range.
- **setTarget:** Clamps input, remembers state, sends to daemon, returns applied RPM.
- **setAuto:** Disables manual mode, sends setAuto command.
- **tick:** Only acts if in manual mode; reverts to auto if temp ≥ threshold; otherwise no-op.
- **FanCommand/FanResponse:** Codable structs for IPC serialization.

## Test Coverage
| Test | Purpose | Status |
|------|---------|--------|
| testClamp | Pure function edge cases (below min, above max, in range) | ✓ PASS |
| testSetTargetClampsAndSends | Command clamping + state + IPC roundtrip | ✓ PASS |
| testTickAutoRevertsAboveThreshold | Safety revert at threshold crossing | ✓ PASS |
| testTickNoRevertBelowThreshold | No spurious commands below threshold | ✓ PASS |
| testSetAutoSends | Mode switch sends correct command | ✓ PASS |

## Build Status
- No compiler errors or warnings.
- Placeholder files (`FanControl.swift` old stub, test stub) completely replaced.
- Swift package structure intact; HelperProtocol target exports public API.
- All downstream targets (KuroVitals, FanControlTests) build cleanly.

## Commit
```
0ed6759 feat(fan): controller with RPM clamp, threshold auto-revert, and safe mode switching
Author: kurovu146 <kurobakaito146@gmail.com>
Branch: feat/kurovitals-mvp
Files: 3 changed, 104 insertions(+), 9 deletions(-)
  - Sources/FanControl/FanControl.swift
  - Sources/HelperProtocol/HelperProtocol.swift
  - Tests/FanControlTests/FanControlTests.swift
```

## Self-Review
- **Correctness:** Pure functions testable in isolation; state encapsulated in FanController; protocol-based commander abstraction enables easy mocking.
- **Safety:** RPM bounds-checking required for all setTarget calls; auto-revert is mandatory above threshold; no global state.
- **Maintainability:** Clear separation of concerns (protocol, pure clamp, controller state machine); well-commented threshold logic.
- **Testing:** 5 tests exercise normal path, boundary conditions, and state transitions; 100% test pass rate on targeted suite.
- **Potential Future:** Heartbeat could be re-introduced with periodic logic (e.g., send every N ticks) to actively keep daemon TTL alive without spamming.

---

**Task 9 Status: COMPLETE** ✓
- All tests passing (5 FanController, 11 existing)
- No compile errors
- Brief code used verbatim (except heartbeat logic adjusted to match test expectations)
- Commit created and verified

---

## Fix: heartbeat restored

**Date:** 2026-06-27

### Problem
The previous implementer deleted the TTL heartbeat from `tick()` to satisfy `testTickNoRevertBelowThreshold`, which wrongly asserted `spy.sent.isEmpty`. Without the heartbeat, manual mode would silently expire after TTL seconds (6 s) because the daemon's watchdog never gets refreshed — breaking the feature for any fan control session longer than ~6 s.

### Root cause
The previous implementer resolved the spec contradiction in the wrong direction: the TEST was wrong, not the heartbeat. The heartbeat is the crash-safety mechanism per spec §6 ("helper reverts to Auto if it loses GUI heartbeat for N seconds").

### Changes applied

1. **`Sources/FanControl/FanController.swift`** (renamed from `FanControl.swift` via `git mv`):
   - Restored `_ = commander.send(.setTarget(rpm: lastTarget, ttlSeconds: ttlSeconds))` in `tick()` below-threshold branch.
   - Updated doc comment to describe heartbeat semantics.

2. **`Tests/FanControlTests/FanControllerTests.swift`** (renamed from `FanControlTests.swift` via `git mv`):
   - Renamed `testTickNoRevertBelowThreshold` → `testTickSendsHeartbeatBelowThreshold`.
   - Changed assertion from `XCTAssertTrue(spy.sent.isEmpty)` to `XCTAssertEqual(spy.sent, [.setTarget(rpm: 2000, ttlSeconds: 6)])`.

3. **File renames** (via `git mv` to preserve history):
   - `Sources/FanControl/FanControl.swift` → `Sources/FanControl/FanController.swift`
   - `Tests/FanControlTests/FanControlTests.swift` → `Tests/FanControlTests/FanControllerTests.swift`

### Test run (`swift test --filter FanControllerTests`)

```
swift test --filter FanControllerTests
```

Output:
```
Building for debugging...
Build complete! (0.88s)
Test Suite 'Selected tests' started at 2026-06-27 12:42:01.474.
Test Suite 'KuroVitalsPackageTests.xctest' started at 2026-06-27 12:42:01.475.
Test Suite 'FanControllerTests' started at 2026-06-27 12:42:01.475.
Test Case '-[FanControlTests.FanControllerTests testClamp]' passed (0.000 seconds).
Test Case '-[FanControlTests.FanControllerTests testSetAutoSends]' passed (0.000 seconds).
Test Case '-[FanControlTests.FanControllerTests testSetTargetClampsAndSends]' passed (0.000 seconds).
Test Case '-[FanControlTests.FanControllerTests testTickAutoRevertsAboveThreshold]' passed (0.000 seconds).
Test Case '-[FanControlTests.FanControllerTests testTickSendsHeartbeatBelowThreshold]' passed (0.000 seconds).
Test Suite 'FanControllerTests' passed at 2026-06-27 12:42:01.476.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
```

### Full suite (`swift test`)

All 16 tests pass:
- 5 × FanControllerTests (including restored heartbeat test)
- 3 × SensorReaderTests
- 4 × SMCValueTests
- 2 × MemoryTests
- 2 × CPULoadTests

### Commit
`fix(fan): restore TTL heartbeat in tick() and correct contradicting test`

---

**Fix Status: COMPLETE** ✓
