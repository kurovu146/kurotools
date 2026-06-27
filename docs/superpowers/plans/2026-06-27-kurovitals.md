# KuroVitals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app (Swift) showing live CPU temp / CPU% / RAM / fan RPM, with manual fan RPM control via a root helper, on a MacBook Pro M2 Pro.

**Architecture:** Swift Package Manager multi-target project. A user-level GUI app (`NSStatusItem`, activation policy `.accessory`) reads CPU%/RAM via mach APIs and temp/fan via SMC (IOKit, read-only). Fan *writes* go through a privileged LaunchDaemon helper over a Unix-domain socket; the helper enforces a TTL watchdog that reverts the fan to Auto if the GUI stops sending heartbeats (crash-safety).

**Tech Stack:** Swift 5.9+, Swift Package Manager, AppKit, IOKit (`AppleSMC`), Foundation, XCTest. No third-party dependencies.

## Global Constraints

- Target machine: MacBook Pro 14" Apple **M2 Pro** (Mac14,9), macOS **26.5.1**, 16GB RAM. Apple Silicon only — do not assume Intel SMC keys/types.
- No Apple Developer account; app is **self-signed ad-hoc**, runs **local only**, no notarization.
- **Writing SMC requires root** → all fan writes go through the helper daemon. The GUI app never runs as root.
- SMC values on Apple Silicon are commonly type `flt ` (32-bit IEEE float), not Intel's `fpe2`. Verify exact types in the Spike (Task 4/5) before trusting any read/write.
- Safety is non-negotiable: clamp RPM to `[F0Mn, F0Mx]`; auto-revert to Auto at the over-temp threshold (default **95°C**) and on GUI heartbeat loss.
- Conventional Commits for messages. Commit after each task. Do **not** `git push` (wait for review). No co-author trailer.
- Default temp threshold 95°C, refresh interval 1.5s, fan heartbeat TTL 6s, app code at `~/Dev/kurovitals`.

---

## File Structure

```
kurovitals/
├── Package.swift
├── Sources/
│   ├── SMCKit/                  # IOKit SMC read/write (generic, key-agnostic)
│   │   ├── SMCConnection.swift  # open/close AppleSMC user client, call struct
│   │   ├── SMCKey.swift         # FourCC key + DataType helpers
│   │   ├── SMCValue.swift       # raw bytes -> typed value (flt/fpe2/ui8/ui16...)
│   │   └── SMC.swift            # high-level: readKey, readAllKeys, writeKey
│   ├── SystemStats/
│   │   ├── CPULoad.swift        # host_processor_info delta -> %
│   │   └── Memory.swift         # vm_statistics64 -> used/total GB
│   ├── SensorReader/
│   │   └── SensorReader.swift   # Snapshot struct + aggregation (temp avg, fan)
│   ├── FanControl/
│   │   ├── FanController.swift  # clamp/auto/manual/safety logic
│   │   └── HelperClient.swift   # socket client to daemon
│   ├── HelperProtocol/
│   │   └── HelperProtocol.swift # shared request/response codable, socket path
│   ├── kurovitals-helper/
│   │   └── main.swift           # root daemon: socket server, SMC write, TTL watchdog
│   └── KuroVitals/              # GUI executable (.accessory)
│       ├── main.swift           # NSApplication bootstrap
│       ├── AppDelegate.swift    # wire-up, timer
│       ├── MenuBarController.swift # NSStatusItem render + dropdown
│       └── Settings.swift       # UserDefaults: toggles, threshold
├── Tests/
│   ├── SMCKitTests/SMCValueTests.swift
│   ├── SystemStatsTests/CPULoadTests.swift
│   ├── SystemStatsTests/MemoryTests.swift
│   ├── SensorReaderTests/SensorReaderTests.swift
│   └── FanControlTests/FanControllerTests.swift
├── scripts/
│   ├── install-helper.sh
│   ├── uninstall-helper.sh
│   ├── install-app.sh           # LaunchAgent autostart for the GUI
│   └── build-release.sh
└── docs/superpowers/
    ├── specs/2026-06-27-kurovitals-design.md
    └── plans/2026-06-27-kurovitals.md   # this file
```

---

### Task 1: Scaffold SwiftPM multi-target project

**Files:**
- Create: `Package.swift`
- Create: `Sources/SMCKit/SMC.swift` (placeholder type so target compiles)
- Create: `Tests/SMCKitTests/SMCValueTests.swift` (one trivially-passing test)

**Interfaces:**
- Produces: a buildable package with targets `SMCKit`, `SystemStats`, `SensorReader`, `FanControl`, `HelperProtocol`, executables `kurovitals-helper`, `KuroVitals`, and test targets.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KuroVitals",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "HelperProtocol"),
        .target(name: "SMCKit"),
        .target(name: "SystemStats"),
        .target(name: "SensorReader", dependencies: ["SMCKit", "SystemStats"]),
        .target(name: "FanControl", dependencies: ["SMCKit", "HelperProtocol"]),
        .executableTarget(
            name: "kurovitals-helper",
            dependencies: ["SMCKit", "HelperProtocol"]),
        .executableTarget(
            name: "KuroVitals",
            dependencies: ["SensorReader", "FanControl", "HelperProtocol"]),
        .testTarget(name: "SMCKitTests", dependencies: ["SMCKit"]),
        .testTarget(name: "SystemStatsTests", dependencies: ["SystemStats"]),
        .testTarget(name: "SensorReaderTests", dependencies: ["SensorReader"]),
        .testTarget(name: "FanControlTests", dependencies: ["FanControl"]),
    ]
)
```

- [ ] **Step 2: Create minimal source + test so all targets compile**

`Sources/SMCKit/SMC.swift`:
```swift
import Foundation

/// Public entry point; real implementation added in later tasks.
public enum SMCKit {
    public static let version = "0.1.0"
}
```

Create empty-but-compiling stub files for each other source listed in File Structure that a target needs to build (each can contain a single `import Foundation` + a placeholder type). Keep them minimal; later tasks replace them.

`Tests/SMCKitTests/SMCValueTests.swift`:
```swift
import XCTest
@testable import SMCKit

final class SMCValueTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertEqual(SMCKit.version, "0.1.0")
    }
}
```

- [ ] **Step 3: Build and test**

Run: `cd ~/Dev/kurovitals && swift build`
Expected: builds with no errors.
Run: `swift test`
Expected: 1 test passes.

- [ ] **Step 4: Add `.gitignore` and commit**

`.gitignore`:
```
.build/
*.xcodeproj
.DS_Store
.swiftpm/
```

```bash
git add -A
git commit -m "chore: scaffold KuroVitals SwiftPM multi-target project"
```

---

### Task 2: SMCKit — connection, readKey, value parsing

**Files:**
- Create: `Sources/SMCKit/SMCConnection.swift`
- Create: `Sources/SMCKit/SMCKey.swift`
- Create: `Sources/SMCKit/SMCValue.swift`
- Modify: `Sources/SMCKit/SMC.swift`
- Test: `Tests/SMCKitTests/SMCValueTests.swift`

**Interfaces:**
- Produces:
  - `SMCKey` with `init(_ string: String)` (4-char FourCC) and `var fourCC: UInt32`.
  - `enum SMCDataType: String` cases incl. `.flt`, `.fpe2`, `.ui8`, `.ui16`, `.ui32`, `.si16`, `.unknown`.
  - `struct SMCValue { let key: SMCKey; let dataType: SMCDataType; let bytes: [UInt8]; var double: Double }` — `double` decodes bytes per type.
  - `final class SMC` with `init() throws`, `func read(_ key: SMCKey) throws -> SMCValue`, `deinit` closing the connection.
  - `enum SMCError: Error { case driverNotFound, openFailed(kern_return_t), keyNotFound(SMCKey), readFailed(UInt8) }`

- [ ] **Step 1: Write the failing test for value decoding (pure, no hardware)**

`Tests/SMCKitTests/SMCValueTests.swift`:
```swift
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
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter SMCValueTests`
Expected: FAIL (types not defined).

- [ ] **Step 3: Implement `SMCKey` and `SMCValue`**

`Sources/SMCKit/SMCKey.swift`:
```swift
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
```

`Sources/SMCKit/SMCValue.swift`:
```swift
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
```

- [ ] **Step 4: Implement `SMCConnection` (IOKit) and `SMC.read`**

`Sources/SMCKit/SMCConnection.swift`:
```swift
import Foundation
import IOKit

// Mirror of the AppleSMC param struct (matches SMCKit by beltex; works on Apple Silicon).
struct SMCParamStruct {
    struct SMCVersion {
        var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0
        var reserved: UInt8 = 0; var release: UInt16 = 0
    }
    struct SMCPLimitData {
        var version: UInt16 = 0; var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0
    }
    struct SMCKeyInfoData {
        var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0
    }
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

// Selectors used in SMCParamStruct.data8
enum SMCSelector: UInt8 {
    case readKey       = 5
    case writeKey      = 6
    case getKeyFromIndex = 8
    case getKeyInfo    = 9
}

let kSMCKernelIndex: UInt32 = 2  // kIOConnectMethodScalarIStructI index for AppleSMC

final class SMCConnection {
    private var connection: io_connect_t = 0

    init() throws {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.driverNotFound }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard kr == kIOReturnSuccess else { throw SMCError.openFailed(kr) }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    /// Low-level call into AppleSMC.
    func call(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        let inSize = MemoryLayout<SMCParamStruct>.stride
        let kr = withUnsafeMutablePointer(to: &output) { outPtr in
            withUnsafePointer(to: &input) { inPtr in
                IOConnectCallStructMethod(connection, kSMCKernelIndex,
                                          inPtr, inSize, outPtr, &outSize)
            }
        }
        guard kr == kIOReturnSuccess else { throw SMCError.openFailed(kr) }
        return output
    }
}

func bytesToArray(_ t: SMCParamStruct, count: Int) -> [UInt8] {
    let all = withUnsafeBytes(of: t.bytes) { Array($0) }
    return Array(all.prefix(count))
}
```

`Sources/SMCKit/SMC.swift` (replace stub):
```swift
import Foundation

public enum SMCError: Error, Equatable {
    case driverNotFound
    case openFailed(kern_return_t)
    case keyNotFound(String)
    case readFailed(UInt8)
}

public final class SMC {
    public static let version = "0.1.0"
    private let conn: SMCConnection

    public init() throws { conn = try SMCConnection() }

    /// Read key info (size + type).
    func keyInfo(_ key: SMCKey) throws -> (size: UInt32, type: UInt32) {
        var input = SMCParamStruct()
        input.key = key.fourCC
        input.data8 = SMCSelector.getKeyInfo.rawValue
        let out = try conn.call(&input)
        if out.result == 0x84 { throw SMCError.keyNotFound(key.string) }
        if out.result != 0 { throw SMCError.readFailed(out.result) }
        return (out.keyInfo.dataSize, out.keyInfo.dataType)
    }

    public func read(_ key: SMCKey) throws -> SMCValue {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = key.fourCC
        input.keyInfo.dataSize = info.size
        input.keyInfo.dataType = info.type
        input.data8 = SMCSelector.readKey.rawValue
        let out = try conn.call(&input)
        if out.result == 0x84 { throw SMCError.keyNotFound(key.string) }
        if out.result != 0 { throw SMCError.readFailed(out.result) }
        let bytes = bytesToArray(out, count: Int(info.size))
        return SMCValue(key: key, dataType: SMCDataType(fourCC: info.type), bytes: bytes)
    }
}

// Re-export so `SMCKit.version` references in earlier test keep working.
public enum SMCKit { public static let version = SMC.version }
```

> NOTE for implementer: the earlier `SMCValueTests.testPackageLoads` referenced `SMCKit.version`; keep the `SMCKit` enum so it still compiles.

- [ ] **Step 5: Run tests**

Run: `swift test --filter SMCValueTests`
Expected: PASS (4 tests). These validate the pure decoder; hardware read is verified in Task 4.

- [ ] **Step 6: Commit**

```bash
git add Sources/SMCKit Tests/SMCKitTests
git commit -m "feat(smc): SMC connection, readKey, and typed value decoding"
```

---

### Task 3: SMCKit — enumerate all keys

**Files:**
- Modify: `Sources/SMCKit/SMC.swift`

**Interfaces:**
- Produces: `SMC.keyCount() throws -> Int`, `SMC.key(atIndex: Int) throws -> SMCKey`, `SMC.allKeys() throws -> [SMCKey]`.
- Consumes: `SMCConnection.call`, `SMCSelector.getKeyFromIndex`, key `#KEY` (ui32 count).

- [ ] **Step 1: Implement enumeration**

Append to `Sources/SMCKit/SMC.swift`:
```swift
public extension SMC {
    func keyCount() throws -> Int {
        let v = try read(SMCKey("#KEY"))   // ui32 count of keys
        return Int(v.double)
    }

    func key(atIndex index: Int) throws -> SMCKey {
        var input = SMCParamStruct()
        input.data8 = SMCSelector.getKeyFromIndex.rawValue
        input.data32 = UInt32(index)
        let out = try conn.call(&input)
        if out.result != 0 { throw SMCError.readFailed(out.result) }
        return SMCKey(fourCC: out.key)
    }

    func allKeys() throws -> [SMCKey] {
        let n = try keyCount()
        var keys: [SMCKey] = []
        keys.reserveCapacity(n)
        for i in 0..<n { keys.append(try key(atIndex: i)) }
        return keys
    }
}
```

> `conn` is currently `private`. Change it to `private let conn: SMCConnection` → keep private but this extension is in the same file, so it has access. If you split files later, make `conn` `internal`.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/SMCKit/SMC.swift
git commit -m "feat(smc): enumerate all SMC keys by index"
```

---

### Task 4: SPIKE — dump SMC keys on the real M2 Pro, record findings

**Files:**
- Create: `Sources/smc-dump/main.swift` (temporary diagnostic executable)
- Modify: `Package.swift` (add `smc-dump` executable target depending on `SMCKit`)
- Create: `docs/superpowers/spike-findings.md`

**Interfaces:**
- Produces: `docs/superpowers/spike-findings.md` listing real fan + temp keys, their data types, sample values, and whether reads need root. This **feeds Task 8** (which temp keys to average) and **Task 5** (write types).

- [ ] **Step 1: Add the dump executable to `Package.swift`**

Add to `targets`:
```swift
.executableTarget(name: "smc-dump", dependencies: ["SMCKit"]),
```

- [ ] **Step 2: Write the dump tool**

`Sources/smc-dump/main.swift`:
```swift
import Foundation
import SMCKit

let smc = try SMC()
let keys = try smc.allKeys()
print("Total keys: \(keys.count)\n")

func dump(prefix: String, label: String) {
    print("== \(label) (prefix \(prefix)) ==")
    for k in keys where k.string.hasPrefix(prefix) {
        if let v = try? smc.read(k) {
            print(String(format: "  %@  type=%@  size=%d  value=%.3f",
                         k.string, v.dataType.rawValue, v.bytes.count, v.double))
        }
    }
    print("")
}

dump(prefix: "F",  label: "Fans")        // F0Ac, F0Mn, F0Mx, F0Md, F0Tg, FNum
dump(prefix: "Tp", label: "P-core temps")
dump(prefix: "Tc", label: "CPU temps")
dump(prefix: "Tg", label: "GPU temps")
dump(prefix: "Te", label: "Efficiency temps")
```

- [ ] **Step 3: Run WITHOUT sudo (verify read needs no root)**

Run: `swift run smc-dump`
Expected: prints total key count and fan/temp keys with values. Record:
- the exact fan keys present (e.g. `F0Ac`, `F0Mn`, `F0Mx`, `F0Md`, `F0Tg`, `FNum`) and their data types,
- which `Tp*`/`Tc*` keys report plausible temps (0 < v < 120),
- confirmation that reads succeeded as a normal user (no sudo).

If reads fail without sudo, re-run `sudo swift run smc-dump` and note that reads need root (this changes Task 13: the GUI would then also need the helper for reads — flag it).

- [ ] **Step 4: Record findings**

Write `docs/superpowers/spike-findings.md` with: fan key list + types, chosen temp keys to average, read-permission result, and any surprises (e.g. multiple fans `FNum > 1`).

- [ ] **Step 5: Commit (keep smc-dump for later diagnostics)**

```bash
git add Package.swift Sources/smc-dump docs/superpowers/spike-findings.md
git commit -m "spike(smc): dump real M2 Pro SMC fan/temp keys and record findings"
```

---

### Task 5: SMCKit — writeKey + SPIKE verify fan write needs root

**Files:**
- Modify: `Sources/SMCKit/SMC.swift`
- Modify: `Sources/smc-dump/main.swift` (add a guarded write-test mode)
- Modify: `docs/superpowers/spike-findings.md`

**Interfaces:**
- Produces: `SMC.write(_ key: SMCKey, bytes: [UInt8]) throws`, and helpers `SMC.setFanMode(_ forced: Bool) throws`, `SMC.setFanTarget(rpm: Double) throws` that encode `F0Md`/`F0Tg` using the data types found in the spike.

- [ ] **Step 1: Implement `write`**

Append to `Sources/SMCKit/SMC.swift`:
```swift
public extension SMC {
    func write(_ key: SMCKey, bytes: [UInt8]) throws {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = key.fourCC
        input.keyInfo.dataSize = info.size
        input.keyInfo.dataType = info.type
        input.data8 = SMCSelector.writeKey.rawValue
        // copy bytes into the 32-byte tuple
        var tuple = input.bytes
        withUnsafeMutableBytes(of: &tuple) { dst in
            for (i, b) in bytes.prefix(Int(info.size)).enumerated() { dst[i] = b }
        }
        input.bytes = tuple
        let out = try conn.call(&input)
        if out.result == 0x84 { throw SMCError.keyNotFound(key.string) }
        if out.result != 0 { throw SMCError.readFailed(out.result) }
    }

    /// F0Md: ui8 mode. 1 = forced/manual, 0 = auto.
    func setFanMode(_ forced: Bool) throws {
        try write(SMCKey("F0Md"), bytes: [forced ? 1 : 0])
    }

    /// F0Tg: target RPM. Encode per the type found in the spike.
    /// Default assumes `flt ` (Apple Silicon). If spike showed `fpe2`, swap encoder.
    func setFanTarget(rpm: Double) throws {
        let f = Float(rpm)
        let le = withUnsafeBytes(of: f) { Array($0) }   // little-endian on arm64
        try write(SMCKey("F0Tg"), bytes: le)
    }
}
```

> The implementer MUST set the `F0Tg` encoder to match the spike's reported data type. If the spike says `fpe2`, replace the body with: `let raw = UInt16(rpm * 4); try write(SMCKey("F0Tg"), bytes: [UInt8(raw >> 8), UInt8(raw & 0xff)])`.

- [ ] **Step 2: Add a guarded write test to smc-dump**

In `Sources/smc-dump/main.swift`, add at the end:
```swift
if CommandLine.arguments.contains("--test-write") {
    print("Reading current F0Tg/F0Md...")
    let beforeMode = try? smc.read(SMCKey("F0Md"))
    let beforeTg  = try? smc.read(SMCKey("F0Tg"))
    print("  before: mode=\(beforeMode?.double ?? -1) target=\(beforeTg?.double ?? -1)")
    let minV = (try? smc.read(SMCKey("F0Mn")))?.double ?? 2000
    let test = minV + 200   // a safe, modest bump above minimum
    do {
        try smc.setFanMode(true)
        try smc.setFanTarget(rpm: test)
        print("  wrote target=\(test). Listen for the fan, then reverting in 5s...")
        sleep(5)
        try smc.setFanMode(false)   // revert to Auto
        print("  reverted to Auto. WRITE SUCCEEDED.")
    } catch {
        print("  WRITE FAILED: \(error)")
        try? smc.setFanMode(false)
    }
}
```

- [ ] **Step 3: SPIKE — run without sudo, then with sudo**

Run: `swift run smc-dump --test-write`
Expected: likely FAILS (write needs root) — record the error.
Run: `sudo swift run smc-dump --test-write`
Expected: succeeds; fan audibly changes for 5s then reverts. Record in spike-findings: **write requires root: yes/no**, F0Tg data type confirmed, fan min/max.

> SAFETY: never leave the machine in forced mode. The tool reverts after 5s; if it crashes, run `sudo swift run smc-dump --revert` (add a `--revert` branch that calls `setFanMode(false)`).

- [ ] **Step 4: Add `--revert` safety branch and commit**

Add to `main.swift`:
```swift
if CommandLine.arguments.contains("--revert") {
    try? smc.setFanMode(false); print("Reverted to Auto."); exit(0)
}
```

```bash
git add Sources/SMCKit/SMC.swift Sources/smc-dump/main.swift docs/superpowers/spike-findings.md
git commit -m "spike(smc): writeKey + verify fan control requires root on M2 Pro"
```

---

### Task 6: SystemStats — CPU load %

**Files:**
- Create: `Sources/SystemStats/CPULoad.swift`
- Test: `Tests/SystemStatsTests/CPULoadTests.swift`

**Interfaces:**
- Produces:
  - `struct CPUTicks { let user, system, idle, nice: UInt64 }`
  - `func cpuUsagePercent(previous: CPUTicks, current: CPUTicks) -> Double` (pure)
  - `final class CPULoadSampler { func sample() -> CPUTicks; func usage() -> Double }` (reads `host_statistics`, stores previous).

- [ ] **Step 1: Write the failing pure test**

`Tests/SystemStatsTests/CPULoadTests.swift`:
```swift
import XCTest
@testable import SystemStats

final class CPULoadTests: XCTestCase {
    func testUsageFromTickDelta() {
        let prev = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let curr = CPUTicks(user: 200, system: 100, idle: 1700, nice: 0)
        // busy delta = (100+50) = 150; total delta = 150 + 850 = 1000 -> 15%
        let pct = cpuUsagePercent(previous: prev, current: curr)
        XCTAssertEqual(pct, 15.0, accuracy: 0.01)
    }

    func testZeroDeltaIsZero() {
        let t = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        XCTAssertEqual(cpuUsagePercent(previous: t, current: t), 0, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter CPULoadTests`
Expected: FAIL (symbols not defined).

- [ ] **Step 3: Implement**

`Sources/SystemStats/CPULoad.swift`:
```swift
import Foundation

public struct CPUTicks: Equatable {
    public let user: UInt64, system: UInt64, idle: UInt64, nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

public func cpuUsagePercent(previous: CPUTicks, current: CPUTicks) -> Double {
    let userD = Double(current.user &- previous.user)
    let sysD  = Double(current.system &- previous.system)
    let niceD = Double(current.nice &- previous.nice)
    let idleD = Double(current.idle &- previous.idle)
    let busy = userD + sysD + niceD
    let total = busy + idleD
    guard total > 0 else { return 0 }
    return busy / total * 100.0
}

public final class CPULoadSampler {
    private var previous: CPUTicks?

    public init() {}

    public func sample() -> CPUTicks {
        var count = mach_msg_type_number_t(HOST_CPU_LOAD_INFO_COUNT)
        var info = host_cpu_load_info()
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return CPUTicks(user: 0, system: 0, idle: 0, nice: 0) }
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3))
    }

    /// Returns usage since the previous call (0 on first call).
    public func usage() -> Double {
        let now = sample()
        defer { previous = now }
        guard let prev = previous else { return 0 }
        return cpuUsagePercent(previous: prev, current: now)
    }
}
```

> `host_cpu_load_info.cpu_ticks` is a 4-tuple ordered `(user, system, idle, nice)` per `CPU_STATE_USER/SYSTEM/IDLE/NICE`.

- [ ] **Step 4: Run tests**

Run: `swift test --filter CPULoadTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SystemStats/CPULoad.swift Tests/SystemStatsTests/CPULoadTests.swift
git commit -m "feat(stats): CPU usage percent from host_statistics tick deltas"
```

---

### Task 7: SystemStats — memory used/total

**Files:**
- Create: `Sources/SystemStats/Memory.swift`
- Test: `Tests/SystemStatsTests/MemoryTests.swift`

**Interfaces:**
- Produces:
  - `struct MemoryInfo { let usedBytes: UInt64; let totalBytes: UInt64; var usedGB: Double; var totalGB: Double; var usedPercent: Double }`
  - `func memoryUsed(active: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64) -> UInt64` (pure)
  - `final class MemorySampler { func read() -> MemoryInfo }`

- [ ] **Step 1: Write the failing pure test**

`Tests/SystemStatsTests/MemoryTests.swift`:
```swift
import XCTest
@testable import SystemStats

final class MemoryTests: XCTestCase {
    func testUsedBytesFromPages() {
        // pageSize 16384 (Apple Silicon). active=1000, wired=500, compressed=200 pages.
        let used = memoryUsed(active: 1000, wired: 500, compressed: 200, pageSize: 16384)
        XCTAssertEqual(used, UInt64(1700) * 16384)
    }

    func testGBConversion() {
        let info = MemoryInfo(usedBytes: 8 * 1_073_741_824, totalBytes: 16 * 1_073_741_824)
        XCTAssertEqual(info.usedGB, 8.0, accuracy: 0.001)
        XCTAssertEqual(info.usedPercent, 50.0, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter MemoryTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

`Sources/SystemStats/Memory.swift`:
```swift
import Foundation

public struct MemoryInfo {
    public let usedBytes: UInt64
    public let totalBytes: UInt64
    public init(usedBytes: UInt64, totalBytes: UInt64) {
        self.usedBytes = usedBytes; self.totalBytes = totalBytes
    }
    public var usedGB: Double { Double(usedBytes) / 1_073_741_824.0 }
    public var totalGB: Double { Double(totalBytes) / 1_073_741_824.0 }
    public var usedPercent: Double {
        totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) * 100.0
    }
}

/// "Used" = active + wired + compressed (matches Activity Monitor's memory pressure footprint closely enough).
public func memoryUsed(active: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64) -> UInt64 {
    (active + wired + compressed) * pageSize
}

public final class MemorySampler {
    public init() {}

    public func read() -> MemoryInfo {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let pageSize = UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory
        guard kr == KERN_SUCCESS else { return MemoryInfo(usedBytes: 0, totalBytes: total) }
        let used = memoryUsed(active: UInt64(stats.active_count),
                              wired: UInt64(stats.wire_count),
                              compressed: UInt64(stats.compressor_page_count),
                              pageSize: pageSize)
        return MemoryInfo(usedBytes: used, totalBytes: total)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter MemoryTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SystemStats/Memory.swift Tests/SystemStatsTests/MemoryTests.swift
git commit -m "feat(stats): memory used/total via vm_statistics64"
```

---

### Task 8: SensorReader — combined snapshot

**Files:**
- Create: `Sources/SensorReader/SensorReader.swift`
- Test: `Tests/SensorReaderTests/SensorReaderTests.swift`

**Interfaces:**
- Consumes: `SMC.read`, `SMC.allKeys`, `CPULoadSampler.usage()`, `MemorySampler.read()`.
- Produces:
  - `struct Snapshot { let cpuTempC: Double; let cpuLoadPct: Double; let ramUsedGB: Double; let ramTotalGB: Double; let fanRPM: Double; let fanMin: Double; let fanMax: Double; let fanForced: Bool }`
  - `protocol SMCReading { func read(_ key: SMCKey) throws -> SMCValue; func allKeys() throws -> [SMCKey] }` (so `SMC` conforms and tests can mock).
  - `func averageTemp(_ values: [Double]) -> Double` (pure: filters 0 < v < 120, averages; 0 if none).
  - `final class SensorReader { init(smc: SMCReading, cpu: CPULoadSampler, mem: MemorySampler, tempKeyPrefixes: [String]); func snapshot() -> Snapshot }`

- [ ] **Step 1: Write the failing test for `averageTemp` + snapshot aggregation with a mock SMC**

`Tests/SensorReaderTests/SensorReaderTests.swift`:
```swift
import XCTest
@testable import SensorReader
@testable import SMCKit

final class FakeSMC: SMCReading {
    var values: [String: SMCValue] = [:]
    var keys: [SMCKey] = []
    func read(_ key: SMCKey) throws -> SMCValue {
        guard let v = values[key.string] else { throw SMCError.keyNotFound(key.string) }
        return v
    }
    func allKeys() throws -> [SMCKey] { keys }
}

final class SensorReaderTests: XCTestCase {
    func testAverageTempFiltersOutliers() {
        // 0 and 200 are invalid; average of 40 and 50 = 45
        XCTAssertEqual(averageTemp([0, 40, 50, 200]), 45, accuracy: 0.01)
        XCTAssertEqual(averageTemp([]), 0, accuracy: 0.01)
    }

    func testSnapshotReadsFanAndTemp() {
        let fake = FakeSMC()
        func flt(_ k: String, _ v: Double) -> SMCValue {
            let f = Float(v); let le = withUnsafeBytes(of: f) { Array($0) }
            return SMCValue(key: SMCKey(k), dataType: .flt, bytes: le)
        }
        fake.keys = [SMCKey("Tp01"), SMCKey("Tp05"), SMCKey("F0Ac"),
                     SMCKey("F0Mn"), SMCKey("F0Mx"), SMCKey("F0Md")]
        fake.values = [
            "Tp01": flt("Tp01", 44), "Tp05": flt("Tp05", 46),
            "F0Ac": flt("F0Ac", 2400), "F0Mn": flt("F0Mn", 1800),
            "F0Mx": flt("F0Mx", 6000),
            "F0Md": SMCValue(key: SMCKey("F0Md"), dataType: .ui8, bytes: [1]),
        ]
        let r = SensorReader(smc: fake, cpu: CPULoadSampler(), mem: MemorySampler(),
                             tempKeyPrefixes: ["Tp"])
        let s = r.snapshot()
        XCTAssertEqual(s.cpuTempC, 45, accuracy: 0.01)
        XCTAssertEqual(s.fanRPM, 2400, accuracy: 0.5)
        XCTAssertEqual(s.fanMin, 1800, accuracy: 0.5)
        XCTAssertEqual(s.fanMax, 6000, accuracy: 0.5)
        XCTAssertTrue(s.fanForced)
    }
}
```

- [ ] **Step 2: Make `SMC` conform to `SMCReading`**

Add to `Sources/SMCKit/SMC.swift`:
```swift
public protocol SMCReading {
    func read(_ key: SMCKey) throws -> SMCValue
    func allKeys() throws -> [SMCKey]
}
extension SMC: SMCReading {}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter SensorReaderTests`
Expected: FAIL (`SensorReader`, `averageTemp` not defined).

- [ ] **Step 4: Implement**

`Sources/SensorReader/SensorReader.swift`:
```swift
import Foundation
import SMCKit
import SystemStats

public struct Snapshot {
    public let cpuTempC: Double
    public let cpuLoadPct: Double
    public let ramUsedGB: Double
    public let ramTotalGB: Double
    public let fanRPM: Double
    public let fanMin: Double
    public let fanMax: Double
    public let fanForced: Bool
}

public func averageTemp(_ values: [Double]) -> Double {
    let valid = values.filter { $0 > 0 && $0 < 120 }
    guard !valid.isEmpty else { return 0 }
    return valid.reduce(0, +) / Double(valid.count)
}

public final class SensorReader {
    private let smc: SMCReading
    private let cpu: CPULoadSampler
    private let mem: MemorySampler
    private let tempKeyPrefixes: [String]
    private var cachedTempKeys: [SMCKey]?

    public init(smc: SMCReading, cpu: CPULoadSampler, mem: MemorySampler,
                tempKeyPrefixes: [String] = ["Tp"]) {
        self.smc = smc; self.cpu = cpu; self.mem = mem
        self.tempKeyPrefixes = tempKeyPrefixes
    }

    private func tempKeys() -> [SMCKey] {
        if let c = cachedTempKeys { return c }
        let all = (try? smc.allKeys()) ?? []
        let matched = all.filter { k in tempKeyPrefixes.contains { k.string.hasPrefix($0) } }
        cachedTempKeys = matched
        return matched
    }

    private func readDouble(_ key: SMCKey) -> Double { (try? smc.read(key))?.double ?? 0 }

    public func snapshot() -> Snapshot {
        let temps = tempKeys().map { readDouble($0) }
        let m = mem.read()
        let mode = readDouble(SMCKey("F0Md"))
        return Snapshot(
            cpuTempC: averageTemp(temps),
            cpuLoadPct: cpu.usage(),
            ramUsedGB: m.usedGB,
            ramTotalGB: m.totalGB,
            fanRPM: readDouble(SMCKey("F0Ac")),
            fanMin: readDouble(SMCKey("F0Mn")),
            fanMax: readDouble(SMCKey("F0Mx")),
            fanForced: mode >= 0.5)
    }
}
```

> Adjust `tempKeyPrefixes` default to whatever the spike (Task 4) found best represents CPU temp on this M2 Pro.

- [ ] **Step 5: Run tests**

Run: `swift test --filter SensorReaderTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/SensorReader Sources/SMCKit/SMC.swift Tests/SensorReaderTests
git commit -m "feat(sensors): combined snapshot of temp/CPU/RAM/fan with mockable SMC"
```

---

### Task 9: FanControl — controller logic with clamp + safety (mock helper)

**Files:**
- Create: `Sources/FanControl/FanController.swift`
- Create: `Sources/HelperProtocol/HelperProtocol.swift`
- Test: `Tests/FanControlTests/FanControllerTests.swift`

**Interfaces:**
- Produces (HelperProtocol):
  - `enum FanCommand: Codable, Equatable { case setTarget(rpm: Int, ttlSeconds: Int); case setAuto; case ping }`
  - `struct FanResponse: Codable, Equatable { let ok: Bool; let message: String }`
  - `let kHelperSocketPath = "/var/run/kurovitals.sock"`
- Produces (FanControl):
  - `protocol FanCommanding { func send(_ command: FanCommand) -> FanResponse }`
  - `final class FanController { init(commander: FanCommanding, threshold: Double, ttlSeconds: Int); func setTarget(rpm: Int, min: Int, max: Int) -> Int (returns clamped rpm); func setAuto(); func tick(currentTempC: Double, currentlyForced: Bool) -> Bool (returns true if it auto-reverted) }`
  - `func clampRPM(_ rpm: Int, min: Int, max: Int) -> Int` (pure)

- [ ] **Step 1: Define the shared protocol**

`Sources/HelperProtocol/HelperProtocol.swift`:
```swift
import Foundation

public let kHelperSocketPath = "/var/run/kurovitals.sock"

public enum FanCommand: Codable, Equatable {
    case setTarget(rpm: Int, ttlSeconds: Int)
    case setAuto
    case ping
}

public struct FanResponse: Codable, Equatable {
    public let ok: Bool
    public let message: String
    public init(ok: Bool, message: String) { self.ok = ok; self.message = message }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/FanControlTests/FanControllerTests.swift`:
```swift
import XCTest
@testable import FanControl
import HelperProtocol

final class SpyCommander: FanCommanding {
    var sent: [FanCommand] = []
    var nextResponse = FanResponse(ok: true, message: "ok")
    func send(_ command: FanCommand) -> FanResponse { sent.append(command); return nextResponse }
}

final class FanControllerTests: XCTestCase {
    func testClamp() {
        XCTAssertEqual(clampRPM(500, min: 1800, max: 6000), 1800)
        XCTAssertEqual(clampRPM(9000, min: 1800, max: 6000), 6000)
        XCTAssertEqual(clampRPM(3000, min: 1800, max: 6000), 3000)
    }

    func testSetTargetClampsAndSends() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        let applied = fc.setTarget(rpm: 9000, min: 1800, max: 6000)
        XCTAssertEqual(applied, 6000)
        XCTAssertEqual(spy.sent, [.setTarget(rpm: 6000, ttlSeconds: 6)])
    }

    func testTickAutoRevertsAboveThreshold() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        _ = fc.setTarget(rpm: 2000, min: 1800, max: 6000)
        spy.sent.removeAll()
        let reverted = fc.tick(currentTempC: 96, currentlyForced: true)
        XCTAssertTrue(reverted)
        XCTAssertEqual(spy.sent, [.setAuto])
    }

    func testTickNoRevertBelowThreshold() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        _ = fc.setTarget(rpm: 2000, min: 1800, max: 6000)
        spy.sent.removeAll()
        let reverted = fc.tick(currentTempC: 70, currentlyForced: true)
        XCTAssertFalse(reverted)
        XCTAssertTrue(spy.sent.isEmpty)
    }

    func testSetAutoSends() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        fc.setAuto()
        XCTAssertEqual(spy.sent, [.setAuto])
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter FanControllerTests`
Expected: FAIL.

- [ ] **Step 4: Implement**

`Sources/FanControl/FanController.swift`:
```swift
import Foundation
import HelperProtocol

public protocol FanCommanding {
    func send(_ command: FanCommand) -> FanResponse
}

public func clampRPM(_ rpm: Int, min: Int, max: Int) -> Int {
    Swift.min(Swift.max(rpm, min), max)
}

public final class FanController {
    private let commander: FanCommanding
    private let threshold: Double
    private let ttlSeconds: Int
    public private(set) var isManual = false
    public private(set) var lastTarget: Int = 0

    public init(commander: FanCommanding, threshold: Double, ttlSeconds: Int) {
        self.commander = commander; self.threshold = threshold; self.ttlSeconds = ttlSeconds
    }

    /// Clamp, remember, and send. Returns the actually-applied RPM.
    @discardableResult
    public func setTarget(rpm: Int, min: Int, max: Int) -> Int {
        let applied = clampRPM(rpm, min: min, max: max)
        _ = commander.send(.setTarget(rpm: applied, ttlSeconds: ttlSeconds))
        isManual = true; lastTarget = applied
        return applied
    }

    public func setAuto() {
        _ = commander.send(.setAuto)
        isManual = false
    }

    /// Called each refresh. Re-sends heartbeat while manual; auto-reverts on over-temp.
    /// Returns true if it auto-reverted this tick.
    @discardableResult
    public func tick(currentTempC: Double, currentlyForced: Bool) -> Bool {
        guard isManual else { return false }
        if currentTempC >= threshold {
            setAuto()
            return true
        }
        // heartbeat: refresh the TTL so the daemon keeps manual mode alive
        _ = commander.send(.setTarget(rpm: lastTarget, ttlSeconds: ttlSeconds))
        return false
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter FanControllerTests`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/FanControl/FanController.swift Sources/HelperProtocol Tests/FanControlTests
git commit -m "feat(fan): controller with RPM clamp, heartbeat, and over-temp auto-revert"
```

---

### Task 10: HelperClient — socket transport (GUI side)

**Files:**
- Create: `Sources/FanControl/HelperClient.swift`

**Interfaces:**
- Consumes: `FanCommand`, `FanResponse`, `kHelperSocketPath`.
- Produces: `final class HelperClient: FanCommanding { init(socketPath: String); func send(_ command: FanCommand) -> FanResponse }` — connects to the Unix socket, sends one newline-delimited JSON request, reads one JSON response. On any failure returns `FanResponse(ok: false, message: ...)` (never throws — GUI must stay alive if the helper is absent).

- [ ] **Step 1: Implement the client**

`Sources/FanControl/HelperClient.swift`:
```swift
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
        guard n > 0,
              let resp = try? JSONDecoder().decode(FanResponse.self,
                          from: Data(buf[0..<n]).split(separator: 0x0A).first.map(Data.init) ?? Data(buf[0..<n]))
        else { return FanResponse(ok: false, message: "no/invalid response") }
        return resp
    }
}
```

- [ ] **Step 2: Build (no unit test — exercised in Task 12 integration)**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/FanControl/HelperClient.swift
git commit -m "feat(fan): Unix-socket helper client (fails soft when helper absent)"
```

---

### Task 11: Helper daemon — root socket server with TTL watchdog

**Files:**
- Create: `Sources/kurovitals-helper/main.swift`

**Interfaces:**
- Consumes: `SMC.setFanMode`, `SMC.setFanTarget`, `FanCommand`, `FanResponse`, `kHelperSocketPath`.
- Produces: a long-running root process that listens on `kHelperSocketPath`, applies fan commands via SMC, and reverts to Auto when no `setTarget` heartbeat arrives within its TTL.

- [ ] **Step 1: Implement the daemon**

`Sources/kurovitals-helper/main.swift`:
```swift
import Foundation
import SMCKit
import HelperProtocol

// Single-threaded accept loop + a 1s watchdog timer on a background queue.
final class Daemon {
    let smc: SMC
    var deadline: Date?          // when current manual mode expires
    let lock = NSLock()

    init() throws { smc = try SMC() }

    func handle(_ cmd: FanCommand) -> FanResponse {
        switch cmd {
        case .ping:
            return FanResponse(ok: true, message: "pong")
        case .setAuto:
            do { try smc.setFanMode(false); lock.lock(); deadline = nil; lock.unlock()
                 return FanResponse(ok: true, message: "auto") }
            catch { return FanResponse(ok: false, message: "\(error)") }
        case let .setTarget(rpm, ttl):
            // Validate: positive rpm, bounded ttl.
            guard rpm > 0, rpm < 12000, ttl > 0, ttl <= 60 else {
                return FanResponse(ok: false, message: "invalid args")
            }
            do {
                try smc.setFanMode(true)
                try smc.setFanTarget(rpm: Double(rpm))
                lock.lock(); deadline = Date().addingTimeInterval(TimeInterval(ttl)); lock.unlock()
                return FanResponse(ok: true, message: "target \(rpm)")
            } catch { return FanResponse(ok: false, message: "\(error)") }
        }
    }

    func watchdogTick() {
        lock.lock(); let d = deadline; lock.unlock()
        if let d = d, Date() > d {
            try? smc.setFanMode(false)
            lock.lock(); deadline = nil; lock.unlock()
            FileHandle.standardError.write("watchdog: reverted to Auto\n".data(using: .utf8)!)
        }
    }
}

func makeSocket(path: String) -> Int32 {
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = path.utf8CString
    withUnsafeMutablePointer(to: &addr.sun_path) {
        $0.withMemoryRebound(to: CChar.self, capacity: bytes.count) { dst in
            bytes.withUnsafeBufferPointer { dst.update(from: $0.baseAddress!, count: bytes.count) }
        }
    }
    _ = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    // Local single-user machine: allow the console user to connect.
    chmod(path, 0o666)
    listen(fd, 8)
    return fd
}

let daemon = try Daemon()
let listenFD = makeSocket(path: kHelperSocketPath)

// Watchdog on a background timer.
let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "watchdog"))
timer.schedule(deadline: .now() + 1, repeating: 1.0)
timer.setEventHandler { daemon.watchdogTick() }
timer.resume()

// On termination signals, revert to Auto.
signal(SIGTERM) { _ in try? SMC().setFanMode(false); exit(0) }
signal(SIGINT)  { _ in try? SMC().setFanMode(false); exit(0) }

while true {
    let clientFD = accept(listenFD, nil, nil)
    if clientFD < 0 { continue }
    var buf = [UInt8](repeating: 0, count: 1024)
    let n = read(clientFD, &buf, buf.count)
    if n > 0 {
        let line = Data(buf[0..<n]).split(separator: 0x0A).first.map(Data.init) ?? Data(buf[0..<n])
        let resp: FanResponse
        if let cmd = try? JSONDecoder().decode(FanCommand.self, from: line) {
            resp = daemon.handle(cmd)
        } else {
            resp = FanResponse(ok: false, message: "bad request")
        }
        if var out = try? JSONEncoder().encode(resp) { out.append(0x0A)
            _ = out.withUnsafeBytes { write(clientFD, $0.baseAddress, out.count) } }
    }
    close(clientFD)
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Manual smoke test (two terminals)**

Terminal A: `sudo .build/debug/kurovitals-helper`
Terminal B:
```bash
printf '{"ping":{}}\n' | nc -U /var/run/kurovitals.sock
```
Expected: `{"ok":true,"message":"pong"}`. (If `FanCommand` JSON shape differs, encode via a tiny `swift run smc-dump`-style check; the exact JSON is produced by `JSONEncoder` on the enum — confirm the real shape and document it.)

> Verify the watchdog: send a `setTarget` with `ttlSeconds: 3`, then stop sending; within ~4s the helper logs "reverted to Auto" and the fan returns to Auto. Confirm by reading `F0Md` with `swift run smc-dump`.

- [ ] **Step 4: Commit**

```bash
git add Sources/kurovitals-helper/main.swift
git commit -m "feat(helper): root daemon applies fan SMC writes with TTL watchdog"
```

---

### Task 12: Helper install/uninstall scripts (LaunchDaemon)

**Files:**
- Create: `scripts/build-release.sh`
- Create: `scripts/install-helper.sh`
- Create: `scripts/uninstall-helper.sh`

**Interfaces:**
- Produces: `/Library/LaunchDaemons/com.kuro.kurovitals.helper.plist` loaded via `launchctl`, helper binary at `/usr/local/libexec/kurovitals-helper`.

- [ ] **Step 1: Release build script**

`scripts/build-release.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
echo "Built: .build/release/KuroVitals and .build/release/kurovitals-helper"
```

- [ ] **Step 2: Install script (run with sudo)**

`scripts/install-helper.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=.build/release/kurovitals-helper
[ -f "$BIN" ] || { echo "Run scripts/build-release.sh first"; exit 1; }

sudo install -m 755 -o root -g wheel "$BIN" /usr/local/libexec/kurovitals-helper

PLIST=/Library/LaunchDaemons/com.kuro.kurovitals.helper.plist
sudo tee "$PLIST" >/dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.kuro.kurovitals.helper</string>
  <key>ProgramArguments</key>
  <array><string>/usr/local/libexec/kurovitals-helper</string></array>
  <key>KeepAlive</key><true/>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>/var/log/kurovitals-helper.log</string>
</dict>
</plist>
EOF

sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"
sudo launchctl unload "$PLIST" 2>/dev/null || true
sudo launchctl load "$PLIST"
echo "Helper installed and loaded."
```

- [ ] **Step 3: Uninstall script**

`scripts/uninstall-helper.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
PLIST=/Library/LaunchDaemons/com.kuro.kurovitals.helper.plist
sudo launchctl unload "$PLIST" 2>/dev/null || true
sudo rm -f "$PLIST" /usr/local/libexec/kurovitals-helper
sudo rm -f /var/run/kurovitals.sock
echo "Helper uninstalled. Fan returns to system Auto on next boot/SMC reset."
```

- [ ] **Step 4: Make executable, test install path**

```bash
chmod +x scripts/*.sh
./scripts/build-release.sh
./scripts/install-helper.sh
```
Expected: helper loads; `sudo launchctl list | grep kurovitals` shows it; `printf '{"ping":{}}\n' | nc -U /var/run/kurovitals.sock` returns pong.

- [ ] **Step 5: Commit**

```bash
git add scripts/
git commit -m "chore(helper): build, install, and uninstall scripts for LaunchDaemon"
```

---

### Task 13: MenuBarController — live NSStatusItem rendering

**Files:**
- Create: `Sources/KuroVitals/MenuBarController.swift`
- Create: `Sources/KuroVitals/Settings.swift`

**Interfaces:**
- Consumes: `Snapshot`, `Settings`.
- Produces:
  - `struct Settings { var showTemp/showCPU/showRAM/showFan: Bool; var thresholdC: Double; var refreshSeconds: Double }` backed by `UserDefaults`.
  - `func formatBar(_ s: Snapshot, _ settings: Settings) -> String` (pure, unit-testable).
  - `final class MenuBarController { init(); var statusItem: NSStatusItem; func render(_ s: Snapshot) }`

- [ ] **Step 1: Write a failing pure test for `formatBar`**

`Tests/FanControlTests/FormatBarTests.swift` (reuse FanControl test target to avoid a new one) — OR add to a new `KuroVitalsTests`. Use a new test target; add to `Package.swift`:
```swift
.testTarget(name: "KuroVitalsTests", dependencies: ["KuroVitals"]),
```
Make `formatBar` and `Settings` live in the `KuroVitals` target but `public`/`@testable`.

`Tests/KuroVitalsTests/FormatBarTests.swift`:
```swift
import XCTest
@testable import KuroVitals
import SensorReader

final class FormatBarTests: XCTestCase {
    func testAllFields() {
        let s = Snapshot(cpuTempC: 48.4, cpuLoadPct: 12.6, ramUsedGB: 9.13,
                         ramTotalGB: 16, fanRPM: 2400, fanMin: 1800, fanMax: 6000, fanForced: false)
        var st = Settings(); st.showTemp = true; st.showCPU = true; st.showRAM = true; st.showFan = true
        XCTAssertEqual(formatBar(s, st), "48° 13% 9.1G 🌀2400")
    }

    func testSubsetFields() {
        let s = Snapshot(cpuTempC: 50, cpuLoadPct: 5, ramUsedGB: 8, ramTotalGB: 16,
                         fanRPM: 2000, fanMin: 1800, fanMax: 6000, fanForced: false)
        var st = Settings(); st.showTemp = true; st.showCPU = false; st.showRAM = false; st.showFan = true
        XCTAssertEqual(formatBar(s, st), "50° 🌀2000")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter FormatBarTests`
Expected: FAIL.

- [ ] **Step 3: Implement `Settings` and `formatBar`**

`Sources/KuroVitals/Settings.swift`:
```swift
import Foundation

public struct Settings {
    public var showTemp = true
    public var showCPU = true
    public var showRAM = true
    public var showFan = true
    public var thresholdC: Double = 95
    public var refreshSeconds: Double = 1.5
    public init() {}

    private static let d = UserDefaults.standard
    public static func load() -> Settings {
        var s = Settings()
        if d.object(forKey: "showTemp") != nil { s.showTemp = d.bool(forKey: "showTemp") }
        if d.object(forKey: "showCPU") != nil { s.showCPU = d.bool(forKey: "showCPU") }
        if d.object(forKey: "showRAM") != nil { s.showRAM = d.bool(forKey: "showRAM") }
        if d.object(forKey: "showFan") != nil { s.showFan = d.bool(forKey: "showFan") }
        if d.object(forKey: "thresholdC") != nil { s.thresholdC = d.double(forKey: "thresholdC") }
        if d.object(forKey: "refreshSeconds") != nil { s.refreshSeconds = d.double(forKey: "refreshSeconds") }
        return s
    }
    public func save() {
        Settings.d.set(showTemp, forKey: "showTemp")
        Settings.d.set(showCPU, forKey: "showCPU")
        Settings.d.set(showRAM, forKey: "showRAM")
        Settings.d.set(showFan, forKey: "showFan")
        Settings.d.set(thresholdC, forKey: "thresholdC")
        Settings.d.set(refreshSeconds, forKey: "refreshSeconds")
    }
}
```

`Sources/KuroVitals/MenuBarController.swift` (formatBar + controller):
```swift
import AppKit
import SensorReader

public func formatBar(_ s: Snapshot, _ settings: Settings) -> String {
    var parts: [String] = []
    if settings.showTemp { parts.append("\(Int(s.cpuTempC.rounded()))°") }
    if settings.showCPU  { parts.append("\(Int(s.cpuLoadPct.rounded()))%") }
    if settings.showRAM  { parts.append(String(format: "%.1fG", s.ramUsedGB)) }
    if settings.showFan  { parts.append("🌀\(Int(s.fanRPM.rounded()))") }
    return parts.joined(separator: " ")
}

public final class MenuBarController {
    public let statusItem: NSStatusItem
    public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    }
    public func render(_ s: Snapshot, settings: Settings) {
        statusItem.button?.title = formatBar(s, settings)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter FormatBarTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/KuroVitals/MenuBarController.swift Sources/KuroVitals/Settings.swift Tests/KuroVitalsTests Package.swift
git commit -m "feat(ui): menu bar formatter + NSStatusItem renderer + Settings"
```

---

### Task 14: Dropdown menu — details, RPM input, Auto, presets, settings

**Files:**
- Modify: `Sources/KuroVitals/MenuBarController.swift`

**Interfaces:**
- Consumes: `Snapshot`, `Settings`, `FanController`.
- Produces: `MenuBarController.buildMenu(snapshot:, settings:, onSetRPM:, onAuto:, onPreset:, onToggle:, onSetThreshold:, onQuit:)` populating `statusItem.menu` with: detail rows, an editable RPM field + Apply, Quiet/Auto/Max presets, current mode, Settings toggles, Quit.

- [ ] **Step 1: Implement the menu builder**

Add to `MenuBarController.swift`:
```swift
public extension MenuBarController {
    func updateMenu(snapshot s: Snapshot, settings: Settings,
                    target: AnyObject,
                    setRPM: Selector, auto: Selector, presetQuiet: Selector,
                    presetMax: Selector, openSettings: Selector, quit: Selector,
                    rpmField: NSTextField) {
        let menu = NSMenu()
        func info(_ t: String) { let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i) }
        info(String(format: "CPU temp: %.0f°C", s.cpuTempC))
        info(String(format: "CPU load: %.0f%%", s.cpuLoadPct))
        info(String(format: "RAM: %.1f / %.0f GB", s.ramUsedGB, s.ramTotalGB))
        info(String(format: "Fan: %.0f rpm (%@)", s.fanRPM, s.fanForced ? "manual" : "auto"))
        info(String(format: "Range: %.0f–%.0f rpm", s.fanMin, s.fanMax))
        menu.addItem(.separator())

        // RPM input row
        let row = NSMenuItem(); let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        rpmField.frame = NSRect(x: 14, y: 3, width: 110, height: 22)
        rpmField.placeholderString = "RPM"
        let apply = NSButton(frame: NSRect(x: 130, y: 1, width: 76, height: 26))
        apply.title = "Apply"; apply.bezelStyle = .rounded; apply.target = target; apply.action = setRPM
        container.addSubview(rpmField); container.addSubview(apply)
        row.view = container; menu.addItem(row)

        let presetQ = NSMenuItem(title: "Quiet (min)", action: presetQuiet, keyEquivalent: ""); presetQ.target = target
        let presetM = NSMenuItem(title: "Max (full)", action: presetMax, keyEquivalent: ""); presetM.target = target
        let autoItem = NSMenuItem(title: "Auto (system)", action: auto, keyEquivalent: ""); autoItem.target = target
        menu.addItem(presetQ); menu.addItem(presetM); menu.addItem(autoItem)
        menu.addItem(.separator())

        let setItem = NSMenuItem(title: "Settings…", action: openSettings, keyEquivalent: ","); setItem.target = target
        let quitItem = NSMenuItem(title: "Quit KuroVitals", action: quit, keyEquivalent: "q"); quitItem.target = target
        menu.addItem(setItem); menu.addItem(quitItem)
        statusItem.menu = menu
    }
}
```

> Settings toggles/threshold can be a simple secondary `NSMenu` submenu or an `NSAlert` with checkboxes invoked by `openSettings`. Keep v1 minimal: a submenu of 4 checkable "Show …" items (toggle `settings.showX`, `save()`, re-render) plus a threshold submenu (90/95/100°C). Implement `openSettings` to toggle these.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/KuroVitals/MenuBarController.swift
git commit -m "feat(ui): dropdown with details, RPM input, presets, Auto, settings, quit"
```

---

### Task 15: App entry point — wire everything + autostart

**Files:**
- Create: `Sources/KuroVitals/main.swift`
- Create: `Sources/KuroVitals/AppDelegate.swift`
- Create: `scripts/install-app.sh`

**Interfaces:**
- Consumes: all prior modules.
- Produces: a runnable `.accessory` menu bar app; LaunchAgent for autostart.

- [ ] **Step 1: AppDelegate wiring**

`Sources/KuroVitals/AppDelegate.swift`:
```swift
import AppKit
import SMCKit
import SystemStats
import SensorReader
import FanControl
import HelperProtocol

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var reader: SensorReader!
    private var menuBar: MenuBarController!
    private var fan: FanController!
    private var timer: Timer?
    private var settings = Settings.load()
    private let rpmField = NSTextField(string: "")
    private var lastSnapshot: Snapshot?

    func applicationDidFinishLaunching(_ note: Notification) {
        let smc = try? SMC()
        guard let smc else {
            NSApp.presentError(NSError(domain: "KuroVitals", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot open SMC"]))
            return
        }
        reader = SensorReader(smc: smc, cpu: CPULoadSampler(), mem: MemorySampler())
        menuBar = MenuBarController()
        fan = FanController(commander: HelperClient(), threshold: settings.thresholdC, ttlSeconds: 6)
        scheduleTimer()
        refresh()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshSeconds, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc private func refresh() {
        let s = reader.snapshot()
        lastSnapshot = s
        menuBar.render(s, settings: settings)
        menuBar.updateMenu(snapshot: s, settings: settings, target: self,
            setRPM: #selector(applyRPM), auto: #selector(setAuto),
            presetQuiet: #selector(presetQuiet), presetMax: #selector(presetMax),
            openSettings: #selector(openSettings), quit: #selector(quit), rpmField: rpmField)
        _ = fan.tick(currentTempC: s.cpuTempC, currentlyForced: s.fanForced)
    }

    @objc private func applyRPM() {
        guard let s = lastSnapshot, let rpm = Int(rpmField.stringValue) else { return }
        let applied = fan.setTarget(rpm: rpm, min: Int(s.fanMin), max: Int(s.fanMax))
        rpmField.stringValue = String(applied)
    }
    @objc private func presetQuiet() { guard let s = lastSnapshot else { return }
        _ = fan.setTarget(rpm: Int(s.fanMin), min: Int(s.fanMin), max: Int(s.fanMax)) }
    @objc private func presetMax() { guard let s = lastSnapshot else { return }
        _ = fan.setTarget(rpm: Int(s.fanMax), min: Int(s.fanMin), max: Int(s.fanMax)) }
    @objc private func setAuto() { fan.setAuto() }
    @objc private func openSettings() { /* toggle submenu handled inline; minimal v1 */ }
    @objc private func quit() { fan.setAuto(); NSApp.terminate(nil) }

    func applicationWillTerminate(_ note: Notification) { fan?.setAuto() }
}
```

`Sources/KuroVitals/main.swift`:
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon; menu bar only
app.run()
```

- [ ] **Step 2: Run the app**

Run: `swift run KuroVitals`
Expected: four values appear in the menu bar (e.g. `48° 12% 9.1G 🌀2400`), updating ~every 1.5s. Click → dropdown shows details + RPM field + presets + Auto + Quit.

> If the helper isn't installed, reads/UI still work; fan commands return "helper not running" (fail-soft). Install helper (Task 12) then test Apply / Quiet / Max / Auto change the fan.

- [ ] **Step 3: Verify against ground truth**

- Compare CPU%/RAM with Activity Monitor (same ballpark).
- Apply a modest RPM above min → audible fan change; press Auto → returns to system control.
- Set threshold low (e.g. 50°C in settings) and force a low RPM under load → app must auto-revert to Auto and post a notification.

- [ ] **Step 4: Autostart LaunchAgent**

`scripts/install-app.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(pwd)/.build/release/KuroVitals"
PLIST="$HOME/Library/LaunchAgents/com.kuro.kurovitals.app.plist"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.kuro.kurovitals.app</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
EOF
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "KuroVitals will start at login."
```

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/install-app.sh
git add Sources/KuroVitals/main.swift Sources/KuroVitals/AppDelegate.swift scripts/install-app.sh
git commit -m "feat(app): wire sensors+fan+menu bar, .accessory app, login autostart"
```

---

## Self-Review

**1. Spec coverage:**
- §1 monitor temp/CPU/RAM/fan → Tasks 6,7,8 + render Task 13. ✓
- §1 control fan by RPM → Tasks 5,9,11 + UI Task 14. ✓
- §2 mach reads / SMC reads / root write → Tasks 6/7, 2-4, 5/11. ✓
- §3 two-process architecture (socket) → Tasks 10,11. ✓
- §4 modules → mapped 1:1 to Sources tree. ✓
- §5 data flow (timer→snapshot→render→control) → Task 15. ✓
- §6 safety (auto-revert over-temp, clamp, revert on exit, TTL watchdog) → Task 9 (over-temp+clamp), Task 11 (TTL), Task 15 (revert on terminate). ✓
- §7 menu bar compact + dropdown → Tasks 13,14. ✓
- §8 spike → Tasks 4,5. ✓
- §9 tests + manual verify → unit tests in 2,6,7,8,9,13; manual in 4,5,11,15. ✓
- §10 install/distribute → Tasks 12,15. ✓
- §11 defaults (name, threshold 95, refresh 1.5s) → Global Constraints + Settings Task 13. ✓
- §12 YAGNI (no graphs/network/fan-curve) → not included. ✓

**2. Placeholder scan:** No "TODO/TBD". Task 14's settings submenu and the F0Tg encoder choice are explicit conditional instructions tied to spike output, not placeholders.

**3. Type consistency:** `Snapshot`, `FanCommand`, `FanResponse`, `SMCReading`, `FanCommanding`, `clampRPM`, `formatBar`, `Settings` names are consistent across producing/consuming tasks. `SMC` conforms to `SMCReading` (Task 8). Helper socket path constant `kHelperSocketPath` shared via `HelperProtocol`.

**Risk note:** SMC float/`fpe2` encoding and exact temp keys are validated by the Task 4/5 spike BEFORE the GUI relies on them; if the spike contradicts assumptions, adjust `SMCValue.double`, `setFanTarget`, and `tempKeyPrefixes` accordingly (each is isolated to one file).
