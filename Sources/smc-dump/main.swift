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

// Safety revert: restore both fans to Auto mode and exit immediately.
// Run as: sudo swift run smc-dump --revert
if CommandLine.arguments.contains("--revert") {
    try? smc.setFanMode(false)
    print("Reverted to Auto.")
    exit(0)
}

dump(prefix: "F",  label: "Fans")        // F0Ac, F0Mn, F0Mx, F0Md, F0Tg, FNum
dump(prefix: "Tp", label: "P-core temps")
dump(prefix: "Tc", label: "CPU temps")
dump(prefix: "Tg", label: "GPU temps")
dump(prefix: "Te", label: "Efficiency temps")

// Write-test: verify SMC fan control requires root, and that flt encoding is correct.
// MUST be run as: sudo swift run smc-dump --test-write
// DO NOT run this without sudo — writes will fail (expected).
if CommandLine.arguments.contains("--test-write") {
    print("\n== Fan Write Test ==")
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
        try smc.setFanMode(true)
        try smc.setFanTarget(rpm: testRPM)
        print("  Wrote forced mode + target=\(Int(testRPM)) RPM to F0Tg & F1Tg.")
        print("  Listen for fan speed change, reverting in 5s...")
        sleep(5)
        try smc.setFanMode(false)
        print("  Reverted to Auto. WRITE SUCCEEDED.")
    } catch {
        print("  WRITE FAILED: \(error)")
        try? smc.setFanMode(false)
    }
}
