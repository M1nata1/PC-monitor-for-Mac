import Foundation
import IOKit

/// Reader for Apple's System Management Controller (`AppleSMC`).
///
/// The SMC exposes a flat namespace of four-character keys ("TC0P", "F0Ac", "PSTR", …).
/// Each key has a type ("flt ", "ui16", "sp78", …) and a payload of up to 32 bytes.
/// We talk to it through the `kSMCHandleYPCEvent` selector of its user client, passing
/// an 80-byte parameter struct in both directions.
///
/// Intel Macs publish most of their thermal sensors here. On Apple silicon the SMC still
/// owns fans, power rails and a few temperatures, while the die sensors live behind
/// `IOHIDEventSystem` (see `HIDSensors`).
final class SMC {

    static let shared = SMC()

    private var connection: io_connect_t = 0
    private let lock = NSLock()
    /// key -> (dataSize, dataType) discovered lazily so repeated reads cost one IOKit call.
    private var keyInfoCache: [String: (size: UInt32, type: String)] = [:]

    private(set) var isAvailable = false

    private init() {
        open()
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: - Connection

    private func open() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else { return }
        connection = conn
        isAvailable = true
    }

    // MARK: - Parameter struct (80 bytes, native endianness)

    private enum Offset {
        static let key = 0            // UInt32, FourCC
        static let keyInfoDataSize = 28   // UInt32
        static let keyInfoDataType = 32   // UInt32, FourCC
        static let keyInfoAttributes = 36 // UInt8
        static let result = 40        // UInt8
        static let status = 41        // UInt8
        static let data8 = 42         // UInt8, selector-within-selector
        static let data32 = 44        // UInt32
        static let bytes = 48         // 32 bytes of payload
        static let structSize = 80
    }

    private enum Selector {
        static let handleYPCEvent: UInt32 = 2
        static let readKey: UInt8 = 5
        static let getKeyFromIndex: UInt8 = 8
        static let getKeyInfo: UInt8 = 9
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: Offset.structSize)
        var outputSize = Offset.structSize
        let result = input.withUnsafeBytes { inputBuffer -> kern_return_t in
            IOConnectCallStructMethod(
                connection,
                Selector.handleYPCEvent,
                inputBuffer.baseAddress,
                Offset.structSize,
                &output,
                &outputSize
            )
        }
        guard result == kIOReturnSuccess else { return nil }
        // A non-zero `result` byte means the SMC rejected the request (unknown key, etc).
        guard output[Offset.result] == 0 else { return nil }
        return output
    }

    // MARK: - Key info

    private func keyInfo(for key: String) -> (size: UInt32, type: String)? {
        if let cached = keyInfoCache[key] { return cached }

        var input = [UInt8](repeating: 0, count: Offset.structSize)
        input.write(UInt32(fourCharCode: key), at: Offset.key)
        input[Offset.data8] = Selector.getKeyInfo

        guard let output = call(input) else { return nil }
        let info = (
            size: output.readUInt32(at: Offset.keyInfoDataSize),
            type: output.readUInt32(at: Offset.keyInfoDataType).fourCharString
        )
        keyInfoCache[key] = info
        return info
    }

    // MARK: - Public reads

    /// Reads a key and decodes it into a `Double` according to its SMC data type.
    func read(_ key: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return readLocked(key)
    }

    /// Reads several keys under a single lock acquisition.
    func read(keys: [String]) -> [String: Double] {
        lock.lock()
        defer { lock.unlock() }
        var result: [String: Double] = [:]
        for key in keys {
            if let value = readLocked(key) { result[key] = value }
        }
        return result
    }

    private func readLocked(_ key: String) -> Double? {
        guard isAvailable, let info = keyInfo(for: key), info.size > 0 else { return nil }

        var input = [UInt8](repeating: 0, count: Offset.structSize)
        input.write(UInt32(fourCharCode: key), at: Offset.key)
        input.write(info.size, at: Offset.keyInfoDataSize)
        input.write(UInt32(fourCharCode: info.type), at: Offset.keyInfoDataType)
        input[Offset.data8] = Selector.readKey

        guard let output = call(input) else { return nil }
        let payload = Array(output[Offset.bytes..<(Offset.bytes + Int(min(info.size, 32)))])
        return SMC.decode(payload, type: info.type)
    }

    /// Every key the controller knows about, in SMC index order. Cached after the first call
    /// because enumeration costs two IOKit round-trips per key.
    private var cachedKeyList: [String]?

    func allKeys() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        if let cachedKeyList { return cachedKeyList }
        guard isAvailable, let count = readLocked("#KEY").map({ Int($0) }), count > 0 else {
            cachedKeyList = []
            return []
        }

        var keys: [String] = []
        keys.reserveCapacity(count)
        for index in 0..<count {
            var input = [UInt8](repeating: 0, count: Offset.structSize)
            input[Offset.data8] = Selector.getKeyFromIndex
            input.write(UInt32(index), at: Offset.data32)
            guard let output = call(input) else { continue }
            let key = output.readUInt32(at: Offset.key).fourCharString
            if !key.isEmpty { keys.append(key) }
        }
        cachedKeyList = keys
        return keys
    }

    /// The data type reported for a key ("flt ", "ui16", …), or nil if the key is absent.
    func type(of key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return keyInfo(for: key)?.type
    }

    // MARK: - Decoding

    /// SMC payloads are big-endian. Fixed-point types encode the fraction width in their name:
    /// "sp78" is signed with 8 fractional bits, "fpe2" is unsigned with 2, and so on.
    static func decode(_ bytes: [UInt8], type: String) -> Double? {
        guard !bytes.isEmpty else { return nil }

        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: raw))

        case "ui8 ", "ui16", "ui32", "ui64":
            var value: UInt64 = 0
            for byte in bytes { value = value << 8 | UInt64(byte) }
            return Double(value)

        case "si8 ", "si16", "si32":
            var value: Int64 = 0
            for byte in bytes { value = value << 8 | Int64(byte) }
            let bits = bytes.count * 8
            // Sign-extend from the payload width.
            if bits < 64, value & (1 << (bits - 1)) != 0 {
                value -= (1 << bits)
            }
            return Double(value)

        case "hex_", "ch8*", "flag":
            var value: UInt64 = 0
            for byte in bytes.prefix(8) { value = value << 8 | UInt64(byte) }
            return Double(value)

        default:
            // fpXY / spXY fixed point, where Y is the number of fractional bits in hex.
            let chars = Array(type)
            if chars.count == 4, chars[0] == "f" || chars[0] == "s", chars[1] == "p",
               let fractionalBits = Int(String(chars[3]), radix: 16) {
                var value: Int64 = 0
                for byte in bytes.prefix(8) { value = value << 8 | Int64(byte) }
                if chars[0] == "s" {
                    let bits = min(bytes.count, 8) * 8
                    if bits < 64, value & (1 << (bits - 1)) != 0 { value -= (1 << bits) }
                }
                return Double(value) / Double(1 << fractionalBits)
            }
            return nil
        }
    }
}

// MARK: - FourCC helpers

private extension UInt32 {
    init(fourCharCode string: String) {
        var result: UInt32 = 0
        for byte in string.utf8.prefix(4) { result = result << 8 | UInt32(byte) }
        // Pad short keys so they still land in the high bytes.
        let missing = Swift.max(0, 4 - string.utf8.count)
        result <<= UInt32(8 * missing)
        self = result
    }

    var fourCharString: String {
        let bytes = [UInt8((self >> 24) & 0xff), UInt8((self >> 16) & 0xff),
                     UInt8((self >> 8) & 0xff), UInt8(self & 0xff)]
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) else { return "" }
        return String(decoding: bytes, as: UTF8.self)
    }
}

private extension Array where Element == UInt8 {
    mutating func write(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(value & 0xff)
        self[offset + 1] = UInt8((value >> 8) & 0xff)
        self[offset + 2] = UInt8((value >> 16) & 0xff)
        self[offset + 3] = UInt8((value >> 24) & 0xff)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}
