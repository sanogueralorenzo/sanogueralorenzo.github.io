import Foundation

/// Bytes the core sent that this build cannot read. The core and Swift ship
/// in one build, so this is always a build bug.
enum WireError: Error, Equatable {
    case truncated
    case malformed(String)
}

/// Writes the positional contract wire format. Lengths, counts, tags and enums
/// are LEB128 varints; numbers are fixed-width little-endian; strings and byte
/// strings are a length followed by their bytes; a UUID is its 16
/// RFC 4122 bytes; dates and intervals are f64 seconds, dates since 2001.
struct WireWriter {
    // MARK: - Variables

    private(set) var bytes: [UInt8] = []

    // MARK: - Actions - Structure

    mutating func writeTag(_ tag: Int) {
        writeVarint(UInt64(tag))
    }

    mutating func writeCount(_ count: Int) {
        writeVarint(UInt64(count))
    }

    mutating func writeEnum(_ rawValue: Int) {
        writeVarint(UInt64(rawValue))
    }

    mutating func writePresence(_ isPresent: Bool) {
        writeBool(isPresent)
    }

    mutating func writeVarint(_ value: UInt64) {
        var remaining = value
        repeat {
            let next = UInt8(remaining & 0x7f)
            remaining >>= 7
            bytes.append(remaining == 0 ? next : next | 0x80)
        } while remaining != 0
    }

    // MARK: - Actions - Values

    mutating func writeBool(_ value: Bool) {
        bytes.append(value ? 1 : 0)
    }

    /// A C# `int`: four bytes.
    mutating func writeInt(_ value: Int) {
        guard let narrow = Int32(exactly: value) else {
            preconditionFailure("\(value) does not fit the contract's 32-bit int")
        }
        withUnsafeBytes(of: narrow.littleEndian) { bytes.append(contentsOf: $0) }
    }

    mutating func writeInt64(_ value: Int64) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    /// A C# `ulong`: eight bytes.
    mutating func writeUInt64(_ value: UInt64) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    mutating func writeDouble(_ value: Double) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
    }

    mutating func writeString(_ value: String) {
        let utf8 = Array(value.utf8)
        writeCount(utf8.count)
        bytes.append(contentsOf: utf8)
    }

    mutating func writeData(_ value: Data) {
        writeCount(value.count)
        bytes.append(contentsOf: value)
    }

    mutating func writeUUID(_ value: UUID) {
        withUnsafeBytes(of: value.uuid) { bytes.append(contentsOf: $0) }
    }

    mutating func writeDate(_ value: Date) {
        writeDouble(value.timeIntervalSinceReferenceDate)
    }

    mutating func writeTimeInterval(_ value: TimeInterval) {
        writeDouble(value)
    }
}

/// Reads what `WireWriter` writes, checking every length against the bytes
/// that remain.
struct WireReader {
    // MARK: - Variables

    private let bytes: [UInt8]
    private var position = 0

    var remaining: Int { bytes.count - position }

    // MARK: - Initializers

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    // MARK: - Actions - Structure

    mutating func readTag() throws(WireError) -> Int {
        try readBounded(UInt64(Int32.max), "tag")
    }

    /// A list's count. Every element occupies at least one byte.
    mutating func readCount() throws(WireError) -> Int {
        try readBounded(UInt64(remaining), "count")
    }

    mutating func readEnum() throws(WireError) -> Int {
        try readBounded(UInt64(Int32.max), "enum")
    }

    mutating func readPresence() throws(WireError) -> Bool {
        try readBool()
    }

    /// Fails unless every byte was read.
    func finish() throws(WireError) {
        guard remaining == 0 else { throw WireError.malformed("\(remaining) unexpected trailing bytes") }
    }

    mutating func readVarint() throws(WireError) -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while shift < 64 {
            let next = try readByte()
            let bits = UInt64(next & 0x7f)
            guard shift < 63 || bits <= 1 else { throw WireError.malformed("varint overflow") }
            value |= bits << shift
            if next & 0x80 == 0 {
                guard next != 0 || shift == 0 else { throw WireError.malformed("overlong varint") }
                return value
            }
            shift += 7
        }
        throw WireError.malformed("varint overflow")
    }

    private mutating func readBounded(_ maximum: UInt64, _ what: String) throws(WireError) -> Int {
        let value = try readVarint()
        guard value <= maximum else { throw WireError.malformed("\(what) \(value) exceeds \(maximum)") }
        return Int(value)
    }

    private mutating func readByte() throws(WireError) -> UInt8 {
        guard position < bytes.count else { throw WireError.truncated }
        defer { position += 1 }
        return bytes[position]
    }

    private mutating func take(_ count: Int) throws(WireError) -> ArraySlice<UInt8> {
        guard count <= remaining else { throw WireError.truncated }
        defer { position += count }
        return bytes[position..<position + count]
    }

    private mutating func littleEndian(_ count: Int) throws(WireError) -> UInt64 {
        let slice = try take(count)
        return slice.reversed().reduce(0) { $0 << 8 | UInt64($1) }
    }

    // MARK: - Actions - Values

    mutating func readBool() throws(WireError) -> Bool {
        switch try readByte() {
        case 0: return false
        case 1: return true
        case let value: throw WireError.malformed("a flag byte is \(value)")
        }
    }

    /// A C# `int`: four bytes.
    mutating func readInt() throws(WireError) -> Int {
        Int(Int32(bitPattern: UInt32(truncatingIfNeeded: try littleEndian(4))))
    }

    mutating func readInt64() throws(WireError) -> Int64 {
        Int64(bitPattern: try littleEndian(8))
    }

    /// A C# `ulong`: eight bytes.
    mutating func readUInt64() throws(WireError) -> UInt64 {
        try littleEndian(8)
    }

    mutating func readDouble() throws(WireError) -> Double {
        Double(bitPattern: try littleEndian(8))
    }

    mutating func readString() throws(WireError) -> String {
        let length = try readBounded(UInt64(remaining), "string length")
        guard let value = String(bytes: try take(length), encoding: .utf8) else {
            throw WireError.malformed("a string is not UTF-8")
        }
        return value
    }

    mutating func readData() throws(WireError) -> Data {
        let length = try readBounded(UInt64(remaining), "byte length")
        return Data(try take(length))
    }

    mutating func readUUID() throws(WireError) -> UUID {
        let raw = Array(try take(16))
        return UUID(
            uuid: (
                raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
                raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]
            ))
    }

    mutating func readDate() throws(WireError) -> Date {
        Date(timeIntervalSinceReferenceDate: try readSeconds("date"))
    }

    mutating func readTimeInterval() throws(WireError) -> TimeInterval {
        try readSeconds("interval")
    }

    private mutating func readSeconds(_ what: String) throws(WireError) -> Double {
        let seconds = try readDouble()
        guard seconds.isFinite else { throw WireError.malformed("a \(what) is not finite") }
        return seconds
    }
}
