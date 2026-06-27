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
