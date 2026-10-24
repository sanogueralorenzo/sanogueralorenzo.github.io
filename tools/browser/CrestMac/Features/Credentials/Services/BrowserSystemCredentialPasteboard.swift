import AppKit

@MainActor
final class BrowserSystemCredentialPasteboard: BrowserCredentialPasteboard {
    private static let concealedType = NSPasteboard.PasteboardType(
        "org.nspasteboard.ConcealedType"
    )
    private static let transientType = NSPasteboard.PasteboardType(
        "org.nspasteboard.TransientType"
    )

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func writeConcealedTransientString(_ value: String) -> Bool {
        pasteboard.declareTypes(
            [.string, Self.concealedType, Self.transientType],
            owner: nil
        )
        guard pasteboard.setString(value, forType: .string) else {
            return false
        }
        pasteboard.setData(Data(), forType: Self.concealedType)
        pasteboard.setData(Data(), forType: Self.transientType)
        return true
    }

    func clearContents() {
        pasteboard.clearContents()
    }
}
