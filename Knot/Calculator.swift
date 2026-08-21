import Foundation

enum Calculator {
    static func evaluate(_ input: String) -> String? {
        var expression = normalized(input.trimmingCharacters(in: .whitespacesAndNewlines))
        let explicitlyRequested = expression.hasPrefix("=")
        if explicitlyRequested {
            expression.removeFirst()
        }

        let operators = CharacterSet(charactersIn: "+-*/%^")
        guard explicitlyRequested || expression.dropFirst().unicodeScalars.contains(where: operators.contains) else {
            return nil
        }

        expression = completedPrefix(of: expression)
        guard !expression.isEmpty else { return nil }

        var parser = Parser(expression)
        guard let value = parser.parse(), value.isFinite else { return nil }
        return String(format: "%.10g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func normalized(_ input: String) -> String {
        input
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
    }

    private static func completedPrefix(of expression: String) -> String {
        var result = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let incompleteOperators = CharacterSet(charactersIn: "+-*/%^")
        while result.count > 1,
              let scalar = result.unicodeScalars.last,
              incompleteOperators.contains(scalar) {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
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
            guard var value = parsePower() else { return nil }
            while let token = peek(), token == "*" || token == "/" || token == "%" {
                advance()
                guard let right = parsePower(), right != 0 || token == "*" else { return nil }
                switch token {
                case "*": value *= right
                case "/": value /= right
                default: value.formTruncatingRemainder(dividingBy: right)
                }
            }
            return value
        }

        private mutating func parsePower() -> Double? {
            guard let value = parseFactor() else { return nil }
            guard peek() == "^" else { return value }
            advance()
            guard let exponent = parsePower() else { return nil }
            return pow(value, exponent)
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
                guard let value = parseExpression() else { return nil }
                if peek() == ")" {
                    advance()
                } else if peek() != nil {
                    return nil
                }
                return value
            }
            return parseNumber()
        }

        private mutating func parseNumber() -> Double? {
            let start = index
            var foundDecimal = false
            while let token = peek(),
                  token.isNumber || token == "," || (token == "." && !foundDecimal) {
                if token == "." { foundDecimal = true }
                advance()
            }
            guard start != index else { return nil }
            let number = String(characters[start..<index])
            guard hasValidThousandsSeparators(number) else { return nil }
            return Double(number.replacingOccurrences(of: ",", with: ""))
        }

        private func hasValidThousandsSeparators(_ number: String) -> Bool {
            let components = number.split(separator: ".", omittingEmptySubsequences: false)
            guard components.count <= 2 else { return false }
            let integer = String(components[0])
            guard integer.contains(",") else { return true }

            let groups = integer.split(separator: ",", omittingEmptySubsequences: false)
            guard let first = groups.first,
                  (1...3).contains(first.count),
                  first.allSatisfy(\.isNumber),
                  groups.dropFirst().allSatisfy({
                      $0.count == 3 && $0.allSatisfy(\.isNumber)
                  }) else {
                return false
            }
            return true
        }

        private func peek() -> Character? {
            characters.indices.contains(index) ? characters[index] : nil
        }

        private mutating func advance() {
            index += 1
        }
    }
}
