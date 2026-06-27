import Foundation
import SMCKit

let smc = try SMC()
let keys = try smc.allKeys()
let fanN = smc.fanCount()
print("Total keys: \(keys.count)  Fans: \(fanN)\n")

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

/// Revert all fans to Auto.
func revertAll() {
    for f in 0..<fanN { try? smc.setFanMode(fan: f, forced: false) }
}

// Safety revert: restore all fans to Auto mode and exit immediately.
// Run as: sudo swift run smc-dump --revert
if CommandLine.arguments.contains("--revert") {
    revertAll()
    print("Reverted all \(fanN) fan(s) to Auto.")
    exit(0)
}

dump(prefix: "F",  label: "Fans")        // F0Ac, F0Mn, F0Mx, F0Md, F0Tg, FNum
dump(prefix: "Tp", label: "P-core temps")
dump(prefix: "Tc", label: "CPU temps")
dump(prefix: "Tg", label: "GPU temps")
dump(prefix: "Te", label: "Efficiency temps")

// High write-test: force a CLEARLY high RPM (~5500) and read back ACTUAL fan speed
// each second to prove (empirically, not by ear) whether the firmware honors the write.
// MUST be run as: sudo .build/debug/smc-dump --test-high
if CommandLine.arguments.contains("--test-high") {
    print("\n== Fan HIGH Write Test (empirical readback, all \(fanN) fan(s)) ==")
    let fansBefore = (0..<fanN).map { i in (try? smc.read(SMCKey("F\(i)Ac")))?.double ?? -1 }
    let fMax = (try? smc.read(SMCKey("F0Mx")))?.double ?? 6800
    let target = min(5500, fMax)
    let beforeDesc = fansBefore.enumerated().map { String(format: "F%dAc=%.0f", $0.offset, $0.element) }.joined(separator: "  ")
    print("  BEFORE: \(beforeDesc) RPM  (target will be \(Int(target)))")
    do {
        for f in 0..<fanN { try smc.setFanMode(fan: f, forced: true) }
        for f in 0..<fanN { try smc.setFanTarget(fan: f, rpm: target) }
        print("  Forced mode + target \(Int(target)) RPM written. Sampling actual RPM for 8s:")
        for i in 1...8 {
            sleep(1)
            let readback = (0..<fanN).map { f -> String in
                let rpm = (try? smc.read(SMCKey("F\(f)Ac")))?.double ?? -1
                return String(format: "F%dAc=%.0f", f, rpm)
            }.joined(separator: "  ")
            print("    t=\(i)s  \(readback) RPM")
        }
        revertAll()
        let fansAfter = (0..<fanN).map { f -> String in
            let rpm = (try? smc.read(SMCKey("F\(f)Ac")))?.double ?? -1
            return String(format: "F%dAc=%.0f", f, rpm)
        }.joined(separator: "  ")
        print("  Reverted to Auto. \(fansAfter)")
        let keyDesc = (0..<fanN).map { "F\($0)Ac" }.joined(separator: "/")
        print("  VERDICT: if \(keyDesc) rose toward \(Int(target)) above, fan control WORKS.")
        print("           if they stayed near \(Int(fansBefore[0])), firmware IGNORES writes (monitor-only).")
    } catch {
        print("  WRITE FAILED: \(error)")
        revertAll()
    }
    exit(0)
}

// Write-test: verify SMC fan control requires root, and that flt encoding is correct.
// MUST be run as: sudo swift run smc-dump --test-write
// DO NOT run this without sudo — writes will fail (expected).
if CommandLine.arguments.contains("--test-write") {
    print("\n== Fan Write Test (all \(fanN) fan(s)) ==")
    print("Reading current fan state...")
    let beforeMode = try? smc.read(SMCKey("F0Md"))
    let beforeTg   = try? smc.read(SMCKey("F0Tg"))
    let beforeTg1  = try? smc.read(SMCKey("F1Tg"))
    print(String(format: "  F0Md=%.0f  F0Tg=%.1f RPM  F1Tg=%.1f RPM",
                 beforeMode?.double ?? -1,
                 beforeTg?.double  ?? -1,
                 beforeTg1?.double ?? -1))
    let minV = (try? smc.read(SMCKey("F0Mn")))?.double ?? 2317
    let testRPM = minV + 200   // safe, modest bump above minimum
    print(String(format: "  Target RPM for test: %.0f (F0Mn=%.0f + 200)", testRPM, minV))
    do {
        for f in 0..<fanN { try smc.setFanMode(fan: f, forced: true) }
        for f in 0..<fanN { try smc.setFanTarget(fan: f, rpm: testRPM) }
        print("  Wrote forced mode + target=\(Int(testRPM)) RPM to all fans.")
        print("  Listen for fan speed change, reverting in 5s...")
        sleep(5)
        revertAll()
        print("  Reverted to Auto. WRITE SUCCEEDED.")
    } catch {
        print("  WRITE FAILED: \(error)")
        revertAll()
    }
}
