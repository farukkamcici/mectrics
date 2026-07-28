import Foundation
import IOKit

/// Minimal AppleSMC user client — reads SMC keys (temperatures, fans).
///
/// The SMC has no public API; this speaks the same `IOConnectCallStructMethod`
/// protocol used by every open-source monitor (Stats, iStats, SMCKit). All calls are
/// read-only. Failures are soft: any error simply yields `nil` and the dependent
/// module reports itself unavailable.
final class SMCClient {
    // MARK: - Wire format (must match AppleSMC's 80-byte SMCParamStruct)

    private struct SMCVersion {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Command: UInt8 {
        case readKey = 5
        case readIndex = 8
        case readKeyInfo = 9
    }

    private static let kernelIndex: UInt32 = 2 // kSMCHandleYPCEvent

    // MARK: - Connection

    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS,
              connection != 0
        else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: - Raw calls

    private func call(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection,
            Self.kernelIndex,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        guard result == KERN_SUCCESS, output.result == 0 else { return nil }
        return output
    }

    /// FourCC string ("TC0P") → UInt32 key.
    static func keyCode(_ name: String) -> UInt32 {
        name.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func keyName(_ code: UInt32) -> String {
        let scalars = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((code >> $0) & 0xFF))) }
        return String(scalars)
    }

    // MARK: - Public surface

    /// Number of keys the SMC exposes (the "#KEY" pseudo-key).
    func keyCount() -> Int {
        guard let data = readData("#KEY"), data.count >= 4 else { return 0 }
        return Int(UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3]))
    }

    /// Key name at an enumeration index.
    func keyName(atIndex index: Int) -> String? {
        var input = SMCParamStruct()
        input.data8 = Command.readIndex.rawValue
        input.data32 = UInt32(index)
        guard let output = call(&input) else { return nil }
        return Self.keyName(output.key)
    }

    func keyInfo(_ name: String) -> KeyInfo? {
        var input = SMCParamStruct()
        input.key = Self.keyCode(name)
        input.data8 = Command.readKeyInfo.rawValue
        guard let output = call(&input) else { return nil }
        return output.keyInfo
    }

    /// Raw bytes of a key's current value.
    func readData(_ name: String) -> [UInt8]? {
        guard let info = keyInfo(name), info.dataSize > 0, info.dataSize <= 32 else { return nil }
        var input = SMCParamStruct()
        input.key = Self.keyCode(name)
        input.keyInfo = info
        input.data8 = Command.readKey.rawValue
        guard let output = call(&input) else { return nil }
        return withUnsafeBytes(of: output.bytes) { raw in
            Array(raw.prefix(Int(info.dataSize)))
        }
    }

    /// Key value decoded to Double for the numeric types monitors care about
    /// (`flt `, `sp78`, `fpe2`, `ui8 `, `ui16`, `ui32`). Unknown types → nil.
    func readValue(_ name: String) -> Double? {
        guard let info = keyInfo(name), let data = readData(name) else { return nil }
        let type = Self.keyName(info.dataType)
        switch type {
        case "flt " where data.count >= 4:
            let bits = data.withUnsafeBytes { $0.load(as: UInt32.self) } // little-endian
            return Double(Float(bitPattern: bits))
        case "sp78" where data.count >= 2:
            let raw = Int16(bitPattern: UInt16(data[0]) << 8 | UInt16(data[1]))
            return Double(raw) / 256
        case "fpe2" where data.count >= 2:
            return Double(UInt16(data[0]) << 8 | UInt16(data[1])) / 4
        case "ui8 " where data.count >= 1:
            return Double(data[0])
        case "ui16" where data.count >= 2:
            return Double(UInt16(data[0]) << 8 | UInt16(data[1]))
        case "ui32" where data.count >= 4:
            return Double(UInt32(data[0]) << 24 | UInt32(data[1]) << 16
                          | UInt32(data[2]) << 8 | UInt32(data[3]))
        default:
            return nil
        }
    }

    /// Enumerates all key names once (used to discover temperature sensors).
    func allKeyNames() -> [String] {
        let count = keyCount()
        guard count > 0, count < 10_000 else { return [] }
        var names: [String] = []
        names.reserveCapacity(count)
        for i in 0..<count {
            if let name = keyName(atIndex: i) { names.append(name) }
        }
        return names
    }
}
