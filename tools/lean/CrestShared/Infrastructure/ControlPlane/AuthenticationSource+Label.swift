import Foundation

extension AuthenticationSource {
    // MARK: - Actions - Answer

    /// The server as the credential prompt names it. The core owns the
    /// formatting; without its answer the prompt uses the generic label. A
    /// prompt never appears without the core in practice, because a challenge's
    /// `handling` cancels it when the core cannot answer.
    static func label(host: String, port: Int, scheme: String?, emptyHostLabel: String) -> String {
        let question = AuthenticationSource(host: host, port: port, scheme: scheme.nonEmpty)
        return (try? CrestCore.answer(question))?.label ?? emptyHostLabel
    }
}
