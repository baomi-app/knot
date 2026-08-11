import Foundation

enum Calculator {
    static func evaluate(_ input: String) -> String? {
        var expression = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitlyRequested = expression.hasPrefix("=")
        if explicitlyRequested {
            expression.removeFirst()
        }

        let operators = CharacterSet(charactersIn: "+-*/%")
        guard explicitlyRequested || expression.dropFirst().unicodeScalars.contains(where: operators.contains) else {
            return nil
        }

        var parser = Parser(expression)
        guard let value = parser.parse(), value.isFinite else { return nil }
        return String(format: "%.10g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private struct Parser {
        private let characters: [Character]
        private var index = 0

        init(_ expression: String) {
            characters = Array(expression.filter { !$0.isWhitespace })
        }

        mutating func parse() -> Double? {
            guard let value = parseExpression(), index == characters.count else { return nil }
            return value
        }

        private mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let token = peek(), token == "+" || token == "-" {
                advance()
                guard let right = parseTerm() else { return nil }
                value = token == "+" ? value + right : value - right
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while let token = peek(), token == "*" || token == "/" || token == "%" {
                advance()
                guard let right = parseFactor(), right != 0 || token == "*" else { return nil }
                switch token {
                case "*": value *= right
                case "/": value /= right
                default: value.formTruncatingRemainder(dividingBy: right)
                }
            }
            return value
        }

        private mutating func parseFactor() -> Double? {
            if peek() == "+" {
                advance()
                return parseFactor()
            }
            if peek() == "-" {
                advance()
                return parseFactor().map { -$0 }
            }
            if peek() == "(" {
                advance()
                guard let value = parseExpression(), peek() == ")" else { return nil }
                advance()
                return value
            }
            return parseNumber()
        }

        private mutating func parseNumber() -> Double? {
            let start = index
            var foundDecimal = false
            while let token = peek(), token.isNumber || (token == "." && !foundDecimal) {
                if token == "." { foundDecimal = true }
                advance()
            }
            guard start != index else { return nil }
            return Double(String(characters[start..<index]))
        }

        private func peek() -> Character? {
            characters.indices.contains(index) ? characters[index] : nil
        }

        private mutating func advance() {
            index += 1
        }
    }
}

