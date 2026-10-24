import Foundation

extension CrestCore {
    /// Where each numbered command leads in the window `windowID`: to a stop
    /// of its Space's sidebar, or to a Space. A command with nowhere to go is
    /// absent.
    func numberedSelections(windowID: UUID) -> [ShortcutCommand: NumberedSelection] {
        guard let answer = try? query(NumberedSelections(windowID: windowID)) else { return [:] }
        return Dictionary(answer.selections.map { ($0.command, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
