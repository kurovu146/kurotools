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
        // 3 bytes explicit padding: Swift omits C's trailing struct padding, which shifts
        // subsequent fields by 4 bytes and causes kIOReturnBadArgument (-536870206).
        // With this pad, stride==12 in both C and Swift, giving correct 80-byte total.
        var _pad: (UInt8, UInt8, UInt8) = (0, 0, 0)
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
        guard kr == kIOReturnSuccess else { throw SMCError.callFailed(kr) }
        return output
    }
}

func bytesToArray(_ t: SMCParamStruct, count: Int) -> [UInt8] {
    let all = withUnsafeBytes(of: t.bytes) { Array($0) }
    return Array(all.prefix(count))
}
