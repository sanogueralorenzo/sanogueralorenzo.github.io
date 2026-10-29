import Foundation

/// Crest's term matching, including Greek final sigma and non-BMP letters.
struct PaletteQuery: Sendable {
    let text: String
    private let terms: [[Unicode.Scalar]]
    var isEmpty: Bool { terms.isEmpty }

    init(_ typed: String) {
        text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        terms = text.unicodeScalars.split(whereSeparator: Self.isWhitespace).map { $0.map(Self.fold) }
    }

    func score(_ title: String, _ detail: String = "") -> Int? {
        guard !isEmpty else { return nil }
        var total = 0
        for term in terms {
            if let points = match(term, title) {
                total += points
            } else if let points = match(term, detail) {
                total += max(0, points - 150)
            } else {
                return nil
            }
        }
        return total / terms.count
    }

    func prefixes(_ value: String) -> Bool {
        guard !isEmpty else { return false }
        let folded = value.unicodeScalars.map { Self.isWhitespace($0) ? Unicode.Scalar(" ") : Self.fold($0) }
        var position = 0
        for (index, term) in terms.enumerated() {
            if index > 0 {
                guard position < folded.count, folded[position] == " " else { return false }
                while position < folded.count, folded[position] == " " { position += 1 }
            }
            for scalar in term {
                guard position < folded.count, folded[position] == scalar else { return false }
                position += 1
            }
        }
        return true
    }

    func abbreviates(_ title: String) -> Int? {
        guard terms.count == 1, terms[0].count >= 2 else { return nil }
        let term = terms[0]
        let scalars = Array(title.unicodeScalars)
        let initials = scalars.enumerated().compactMap { index, scalar in
            !Self.isBoundary(scalar) && (index == 0 || Self.isBoundary(scalars[index - 1])) ? Self.fold(scalar) : nil
        }
        if initials.starts(with: term) { return 250 }
        var found = 0
        for scalar in scalars where found < term.count {
            if Self.fold(scalar) == term[found] { found += 1 }
        }
        return found == term.count ? 150 : nil
    }

    private func match(_ term: [Unicode.Scalar], _ value: String) -> Int? {
        let scalars = Array(value.unicodeScalars)
        guard scalars.count >= term.count else { return nil }
        var best: Int?
        for start in 0...(scalars.count - term.count) {
            guard scalars[start..<(start + term.count)].map(Self.fold).elementsEqual(term) else { continue }
            if start == 0 { return 1_000 }
            if Self.isBoundary(scalars[start - 1]) { return 700 }
            best = 300
        }
        return best
    }

    private static func fold(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        if scalar == "ς" { return "σ" }
        // Rune.ToLowerInvariant folds one scalar rather than expanding a word.
        return scalar.properties.isUppercase ? String(scalar).lowercased().unicodeScalars.first! : scalar
    }
    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII ? scalar == " " || scalar == "\t" : scalar.properties.isWhitespace
    }
    private static func isBoundary(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
            .decimalNumber, .letterNumber, .otherNumber:
            false
        default: true
        }
    }
}

/// A bounded arithmetic parser; no scripting engine or expression evaluation.
struct PaletteCalculation {
    let expression: String
    let value: Double
    var answer: String { String(format: "%.12G", locale: Locale(identifier: "en_US_POSIX"), value) }

    static func read(_ typed: String) -> Self? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= 128, text.contains(where: { $0.isASCII && $0.isNumber }) else {
            return nil
        }
        var parser = Parser(text: Array(text))
        guard let value = try? parser.sum() else { return nil }
        parser.skipSpace()
        guard parser.position == parser.text.count, parser.operated, value.isFinite else { return nil }
        return Self(expression: text, value: value == 0 ? 0 : value)
    }

    private struct Parser {
        enum Invalid: Error { case expression }
        let text: [Character]
        var position = 0
        var depth = 0
        var operated = false
        mutating func sum() throws -> Double {
            var value = try product()
            while true {
                skipSpace()
                if take("+") {
                    value += try product()
                } else if take("-") || take("−") {
                    value -= try product()
                } else {
                    return value
                }
                operated = true
            }
        }
        mutating func product() throws -> Double {
            var value = try power()
            while true {
                skipSpace()
                if take("*") || take("×") || take("x") {
                    value *= try power()
                } else if take("/") || take("÷") {
                    value /= try power()
                } else if take("%") {
                    value = value.truncatingRemainder(dividingBy: try power())
                } else {
                    return value
                }
                operated = true
            }
        }
        mutating func power() throws -> Double {
            let value = try unary()
            skipSpace()
            guard take("^") else { return value }
            operated = true
            return pow(value, try power())
        }
        mutating func unary() throws -> Double {
            skipSpace()
            if take("-") || take("−") {
                operated = true
                return -(try unary())
            }
            if take("+") { return try unary() }
            if take("(") {
                depth += 1
                guard depth <= 32 else { throw Invalid.expression }
                let value = try sum()
                skipSpace()
                guard take(")") else { throw Invalid.expression }
                depth -= 1
                return value
            }
            let start = position
            while position < text.count, (text[position].isASCII && text[position].isNumber) || text[position] == "." {
                position += 1
            }
            guard position > start, let value = Double(String(text[start..<position])) else { throw Invalid.expression }
            return value
        }
        mutating func take(_ character: Character) -> Bool {
            guard position < text.count, text[position] == character else { return false }
            position += 1
            return true
        }
        mutating func skipSpace() {
            while position < text.count, text[position].isWhitespace { position += 1 }
        }
    }
}
