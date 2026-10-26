import Dispatch
import Foundation

/// Frames one page's saved history with the little Crest knows about it.
///
/// The history is opaque. An engine's tagged history carries its own version
/// check, but untagged history predates tagging and is always WebKit's, which
/// WebKit only promises to read back on its own build, so the frame records the
/// OS build that produced it. An untagged blob stamped by anything else is
/// discarded rather than handed to WebKit. The frame also records the URL the
/// page was showing, which is what lets a restore be declined — before the
/// engine is touched at all — when the tab has since been pointed somewhere else.
/// Since version 2 it also carries the page's back and forward history as the
/// core keeps it across engines, opaque here; version 1 frames carry none.
struct BrowserTabStateEnvelope: Equatable, Sendable {
    /// Crest's own framing version, bumped when this layout changes. It is not
    /// WebKit's: the OS build covers that.
    static let currentFormatVersion: UInt16 = 2
    private static let readableFormatVersions: ClosedRange<UInt16> = 1...2
    private static let magic = Data("CRTS".utf8)
    private static let headerByteCount = 12
    private static let historyHeaderByteCount = 4

    let formatVersion: UInt16
    let osBuild: String
    let url: URL?
    let history: Data?
    let interactionState: Data

    /// The OS build this process is running against. Apple ships WebKit in
    /// lockstep with the system, so the system build identifies the writer.
    static var currentOSBuild: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    init(
        interactionState: Data,
        url: URL?,
        history: Data? = nil,
        formatVersion: UInt16 = BrowserTabStateEnvelope.currentFormatVersion,
        osBuild: String = BrowserTabStateEnvelope.currentOSBuild
    ) {
        self.interactionState = interactionState
        self.url = url
        self.history = history
        self.formatVersion = formatVersion
        self.osBuild = osBuild
    }

    /// True when this build of Crest can read the frame, and with it the
    /// core's history it carries.
    var isReadable: Bool {
        Self.readableFormatVersions.contains(formatVersion)
    }

    /// True when this build of Crest may hand the payload to its engine: its
    /// engine's tag decides, or an untagged payload is from this OS build.
    /// Everything else, and a frame that carries only history, is treated as
    /// absent state.
    var isRestorable: Bool {
        isReadable && !interactionState.isEmpty
            && (BrowserEngineInteractionState.isTagged(interactionState) || osBuild == Self.currentOSBuild)
    }

    func encoded() -> Data {
        let osBuildBytes = Data(osBuild.utf8)
        let urlBytes = Data((url?.absoluteString ?? "").utf8)
        // Version 1 frames carry no history.
        let carriesHistory = formatVersion >= 2
        let historyBytes = carriesHistory ? history ?? Data() : Data()
        var encoded = Data(
            capacity: Self.headerByteCount + Self.historyHeaderByteCount + osBuildBytes.count
                + urlBytes.count + historyBytes.count + interactionState.count)
        encoded.append(Self.magic)
        encoded.append(Self.littleEndianBytes(formatVersion))
        encoded.append(Self.littleEndianBytes(UInt16(clamping: osBuildBytes.count)))
        encoded.append(Self.littleEndianBytes(UInt32(clamping: urlBytes.count)))
        if carriesHistory { encoded.append(Self.littleEndianBytes(UInt32(clamping: historyBytes.count))) }
        encoded.append(osBuildBytes)
        encoded.append(urlBytes)
        encoded.append(historyBytes)
        encoded.append(interactionState)
        return encoded
    }

    static func decode(_ data: Data) -> Self? {
        guard data.count >= headerByteCount,
            data.prefix(magic.count) == magic,
            let formatVersion = readUInt16(data, at: 4),
            let osBuildByteCount = readUInt16(data, at: 6).map(Int.init),
            let urlByteCount = readUInt32(data, at: 8).map(Int.init)
        else {
            return nil
        }
        // Version 1 frames carry no history; later ones count its bytes.
        let carriesHistory = formatVersion >= 2
        let historyByteCount = carriesHistory ? readUInt32(data, at: headerByteCount).map(Int.init) : 0
        guard let historyByteCount else { return nil }
        let osBuildStart = data.startIndex + headerByteCount + (carriesHistory ? historyHeaderByteCount : 0)
        let urlStart = osBuildStart + osBuildByteCount
        let historyStart = urlStart + urlByteCount
        let payloadStart = historyStart + historyByteCount
        guard payloadStart <= data.endIndex,
            let osBuild = String(data: data[osBuildStart..<urlStart], encoding: .utf8),
            let address = String(data: data[urlStart..<historyStart], encoding: .utf8)
        else {
            return nil
        }
        return Self(
            interactionState: Data(data[payloadStart..<data.endIndex]),
            url: address.isEmpty ? nil : URL(string: address),
            history: historyByteCount == 0 ? nil : Data(data[historyStart..<payloadStart]),
            formatVersion: formatVersion,
            osBuild: osBuild
        )
    }

    private static func littleEndianBytes(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func littleEndianBytes(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ])
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard data.count >= offset + 2 else { return nil }
        let start = data.startIndex + offset
        return UInt16(data[start]) | (UInt16(data[start + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard data.count >= offset + 4 else { return nil }
        let start = data.startIndex + offset
        return UInt32(data[start])
            | (UInt32(data[start + 1]) << 8)
            | (UInt32(data[start + 2]) << 16)
            | (UInt32(data[start + 3]) << 24)
    }
}
