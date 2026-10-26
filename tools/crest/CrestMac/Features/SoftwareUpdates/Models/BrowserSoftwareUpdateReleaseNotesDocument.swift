import Foundation

struct BrowserSoftwareUpdateReleaseNotesDocument {
    enum BlockKind: Equatable {
        case heading(level: Int)
        case paragraph
        case bullet
        case divider
    }

    struct Block {
        let kind: BlockKind
        let text: AttributedString

        var plainText: String {
            String(text.characters)
        }
    }

    let blocks: [Block]

    init(markdown: String) {
        blocks = Self.parse(markdown)
    }

    private static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraphLines: [String] = []

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                appendParagraph(&paragraphLines, to: &blocks)
                continue
            }
            if isDivider(line) {
                appendParagraph(&paragraphLines, to: &blocks)
                blocks.append(Block(kind: .divider, markdown: ""))
            } else if let heading = heading(from: line) {
                appendParagraph(&paragraphLines, to: &blocks)
                blocks.append(
                    Block(
                        kind: .heading(level: heading.level),
                        markdown: heading.text
                    )
                )
            } else if let bullet = bullet(from: line) {
                appendParagraph(&paragraphLines, to: &blocks)
                blocks.append(Block(kind: .bullet, markdown: bullet))
            } else {
                paragraphLines.append(line)
            }
        }

        appendParagraph(&paragraphLines, to: &blocks)
        return blocks
    }

    private static func appendParagraph(
        _ lines: inout [String],
        to blocks: inout [Block]
    ) {
        guard !lines.isEmpty else { return }
        blocks.append(Block(kind: .paragraph, markdown: lines.joined(separator: " ")))
        lines.removeAll(keepingCapacity: true)
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else {
            return nil
        }
        return (level, String(line.dropFirst(level + 1)))
    }

    private static func bullet(from line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func isDivider(_ line: String) -> Bool {
        line == "---" || line == "***" || line == "___"
    }
}

extension BrowserSoftwareUpdateReleaseNotesDocument.Block {
    fileprivate init(
        kind: BrowserSoftwareUpdateReleaseNotesDocument.BlockKind,
        markdown: String
    ) {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        text =
            (try? AttributedString(markdown: markdown, options: options))
            ?? AttributedString(markdown)

        self.kind = kind
    }
}
