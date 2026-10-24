@MainActor
protocol BrowserCredentialPasteboard: AnyObject {
    var changeCount: Int { get }

    func writeConcealedTransientString(_ value: String) -> Bool
    func clearContents()
}
