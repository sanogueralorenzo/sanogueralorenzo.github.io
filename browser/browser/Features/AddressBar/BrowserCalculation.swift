import Foundation

struct BrowserCalculation {
    private var input: [Character]
    private var position = 0
    static func value(_ text: String) -> String? {
        guard text.count <= 200, text.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/%^()").inverted) != nil,
            text.contains(where: { "+-*/%^".contains($0) }),
            text.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789.+-*/%^() ").contains($0) })
        else { return nil }
        var parser = BrowserCalculation(input: Array(text.filter { !$0.isWhitespace }))
        guard let value = parser.expression(depth: 0), parser.position == parser.input.count, value.isFinite else {
            return nil
        }
        return value.formatted(.number.precision(.significantDigits(1...12)))
    }
    private mutating func expression(depth: Int) -> Double? {
        guard depth < 32, var value = term(depth: depth + 1) else { return nil }
        while let op = peek(), op == "+" || op == "-" {
            position += 1
            guard let other = term(depth: depth + 1) else { return nil }
            value = op == "+" ? value + other : value - other
        }
        return value
    }
    private mutating func term(depth: Int) -> Double? {
        guard var value = factor(depth: depth + 1) else { return nil }
        while let op = peek(), op == "*" || op == "/" || op == "%" {
            position += 1
            guard let other = factor(depth: depth + 1), op == "*" || other != 0 else { return nil }
            value = op == "*" ? value * other : op == "/" ? value / other : value.truncatingRemainder(dividingBy: other)
        }
        return value
    }
    private mutating func factor(depth: Int) -> Double? {
        guard depth < 32 else { return nil }
        if peek() == "-" {
            position += 1
            return factor(depth: depth + 1).map(-)
        }
        if peek() == "+" {
            position += 1
            return factor(depth: depth + 1)
        }
        var value: Double
        if peek() == "(" {
            position += 1
            guard let number = expression(depth: depth + 1), peek() == ")" else { return nil }
            position += 1
            value = number
        } else {
            let start = position
            while let c = peek(), c.isNumber || c == "." { position += 1 }
            guard start < position, let number = Double(String(input[start..<position])) else { return nil }
            value = number
        }
        if peek() == "^" {
            position += 1
            guard let exponent = factor(depth: depth + 1) else { return nil }
            value = pow(value, exponent)
        }
        return value.isFinite ? value : nil
    }
    private func peek() -> Character? { input.indices.contains(position) ? input[position] : nil }
}
