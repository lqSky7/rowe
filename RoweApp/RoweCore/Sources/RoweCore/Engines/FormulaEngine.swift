import Foundation

public struct EvaluatedTableCell: Hashable, Sendable {
    public var displayText: String
    public var numericValue: Double?
    public var error: String?

    public init(displayText: String, numericValue: Double? = nil, error: String? = nil) {
        self.displayText = displayText
        self.numericValue = numericValue
        self.error = error
    }
}

/// Evaluates Craft-compatible table formulas (`=` prefix, 5-decimal rounding, header-aware
/// ABOVE/LEFT/BELOW/RIGHT ranges, cycle detection, and standard aggregate functions).
public struct FormulaEngine: Sendable {
    private static let constants: [String: Double] = [
        "E": M_E,
        "LN2": log(2.0),
        "LN10": log(10.0),
        "LOG2E": log2(M_E),
        "LOG10E": log10(M_E),
        "PI": .pi,
        "SQRT1_2": sqrt(0.5),
        "SQRT2": sqrt(2.0)
    ]

    public init() {}

    public func evaluate(table: TableData) -> [[EvaluatedTableCell]] {
        let rowCount = table.cells.count
        let colCount = table.cells.first?.count ?? 0
        guard rowCount > 0, colCount > 0 else { return [] }

        var cache: [CellCoord: EvalValue] = [:]
        var results: [[EvaluatedTableCell]] = Array(
            repeating: Array(repeating: EvaluatedTableCell(displayText: ""), count: colCount),
            count: rowCount
        )

        for r in 0..<rowCount {
            for c in 0..<colCount {
                let coord = CellCoord(row: r, col: c)
                var visiting = Set<CellCoord>()
                let value = evalCell(coord, in: table, cache: &cache, visiting: &visiting)
                let cell = table.cells[r][c]
                results[r][c] = formatResult(value, format: cell.format, isFormula: cell.rawContent.hasPrefix("="))
            }
        }
        return results
    }

    private struct CellCoord: Hashable {
        let row: Int
        let col: Int
    }

    private enum EvalValue {
        case number(Double)
        case text(String)
        case error(String)
    }

    private func evalCell(
        _ coord: CellCoord,
        in table: TableData,
        cache: inout [CellCoord: EvalValue],
        visiting: inout Set<CellCoord>
    ) -> EvalValue {
        if let cached = cache[coord] { return cached }
        guard coord.row >= 0, coord.row < table.cells.count,
              coord.col >= 0, coord.col < table.cells[coord.row].count else {
            return .error("#REF!")
        }
        if visiting.contains(coord) {
            return .error("#REF!")
        }

        let raw = table.cells[coord.row][coord.col].rawContent
        guard raw.hasPrefix("=") else {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                cache[coord] = .text("")
                return .text("")
            }
            if let num = Double(trimmed) {
                cache[coord] = .number(num)
                return .number(num)
            }
            cache[coord] = .text(raw)
            return .text(raw)
        }

        let expr = String(raw.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        if expr.isEmpty {
            cache[coord] = .error("#ERROR!")
            return .error("#ERROR!")
        }
        if expr.contains("$") {
            cache[coord] = .error("#NAME?")
            return .error("#NAME?")
        }

        visiting.insert(coord)
        defer { visiting.remove(coord) }

        let result = parseAndEval(expr, at: coord, in: table, cache: &cache, visiting: &visiting)
        let rounded: EvalValue
        if case .number(let n) = result {
            if n.isNaN {
                rounded = .error("#VALUE!")
            } else if n.isInfinite {
                rounded = .error("#DIV/0!")
            } else {
                // Craft rounds formula outputs to 5 decimal places before display formatting.
                let factor = 100_000.0
                rounded = .number((n * factor).rounded() / factor)
            }
        } else {
            rounded = result
        }
        cache[coord] = rounded
        return rounded
    }

    private func parseAndEval(
        _ expr: String,
        at origin: CellCoord,
        in table: TableData,
        cache: inout [CellCoord: EvalValue],
        visiting: inout Set<CellCoord>
    ) -> EvalValue {
        let tokens = tokenize(expr)
        var index = 0

        func parseAddSub() -> EvalValue {
            var left = parseMulDiv()
            while index < tokens.count, case .op(let op) = tokens[index], (op == "+" || op == "-") {
                index += 1
                let right = parseMulDiv()
                left = applyBinary(op, left, right)
            }
            return left
        }

        func parseMulDiv() -> EvalValue {
            var left = parseUnary()
            while index < tokens.count, case .op(let op) = tokens[index], (op == "*" || op == "/") {
                index += 1
                let right = parseUnary()
                left = applyBinary(op, left, right)
            }
            return left
        }

        func parseUnary() -> EvalValue {
            if index < tokens.count, case .op(let op) = tokens[index], (op == "-" || op == "+") {
                index += 1
                let val = parseUnary()
                if op == "-" {
                    return applyBinary("*", .number(-1), val)
                }
                return val
            }
            return parsePrimary()
        }

        func parsePrimary() -> EvalValue {
            guard index < tokens.count else { return .error("#ERROR!") }
            switch tokens[index] {
            case .number(let n):
                index += 1
                return .number(n)
            case .lparen:
                index += 1
                let val = parseAddSub()
                if index < tokens.count, case .rparen = tokens[index] {
                    index += 1
                }
                return val
            case .ident(let rawIdent):
                let upper = rawIdent.uppercased()
                index += 1
                if index < tokens.count, case .lparen = tokens[index] {
                    index += 1
                    var args: [EvalArg] = []
                    if index < tokens.count, case .rparen = tokens[index] {
                        index += 1
                    } else {
                        while index < tokens.count {
                            args.append(parseFunctionArg())
                            if index < tokens.count, case .comma = tokens[index] {
                                index += 1
                                continue
                            }
                            if index < tokens.count, case .rparen = tokens[index] {
                                index += 1
                            }
                            break
                        }
                    }
                    return evaluateFunction(upper, args: args, origin: origin, table: table)
                }
                if let c = Self.constants[upper] {
                    return .number(c)
                }
                if let refCoord = parseCellRef(upper) {
                    return evalCell(refCoord, in: table, cache: &cache, visiting: &visiting)
                }
                return .error("#NAME?")
            default:
                return .error("#ERROR!")
            }
        }

        func parseFunctionArg() -> EvalArg {
            if index < tokens.count, case .ident(let raw) = tokens[index] {
                let upper = raw.uppercased()
                if ["ABOVE", "BELOW", "LEFT", "RIGHT"].contains(upper) {
                    index += 1
                    let coords = directionalCoords(upper, origin: origin, table: table)
                    let vals = coords.map { evalCell($0, in: table, cache: &cache, visiting: &visiting) }
                    return .range(vals)
                }
                if index + 2 < tokens.count,
                   case .colon = tokens[index + 1],
                   case .ident(let endRaw) = tokens[index + 2],
                   let startCoord = parseCellRef(upper),
                   let endCoord = parseCellRef(endRaw.uppercased()) {
                    index += 3
                    var vals: [EvalValue] = []
                    for r in min(startCoord.row, endCoord.row)...max(startCoord.row, endCoord.row) {
                        for c in min(startCoord.col, endCoord.col)...max(startCoord.col, endCoord.col) {
                            vals.append(evalCell(CellCoord(row: r, col: c), in: table, cache: &cache, visiting: &visiting))
                        }
                    }
                    return .range(vals)
                }
            }
            return .single(parseAddSub())
        }

        let result = parseAddSub()
        return index < tokens.count ? .error("#ERROR!") : result
    }

    private enum EvalArg {
        case single(EvalValue)
        case range([EvalValue])
    }

    private func evaluateFunction(_ name: String, args: [EvalArg], origin: CellCoord, table: TableData) -> EvalValue {
        let flatValues: [EvalValue] = args.flatMap { arg -> [EvalValue] in
            switch arg {
            case .single(let v): [v]
            case .range(let list): list
            }
        }
        let numbers: [Double] = flatValues.compactMap { v in
            if case .number(let n) = v { return n }
            return nil
        }

        switch name {
        case "SUM":
            return .number(numbers.reduce(0, +))
        case "AVERAGE":
            guard !numbers.isEmpty else { return .error("#DIV/0!") }
            return .number(numbers.reduce(0, +) / Double(numbers.count))
        case "COUNT":
            return .number(Double(numbers.count))
        case "COUNTA":
            let nonEmpty = flatValues.filter {
                if case .text(let s) = $0 { return !s.isEmpty }
                return true
            }.count
            return .number(Double(nonEmpty))
        case "MIN":
            return .number(numbers.min() ?? 0)
        case "MAX":
            return .number(numbers.max() ?? 0)
        case "MEDIAN":
            guard !numbers.isEmpty else { return .number(0) }
            let sorted = numbers.sorted()
            let mid = sorted.count / 2
            return sorted.count % 2 == 1 ? .number(sorted[mid]) : .number((sorted[mid - 1] + sorted[mid]) / 2.0)
        case "MODE":
            guard !numbers.isEmpty else { return .error("#VALUE!") }
            var counts: [Double: Int] = [:]
            for n in numbers { counts[n, default: 0] += 1 }
            let best = counts.max(by: { $0.value < $1.value })?.key ?? numbers[0]
            return .number(best)
        case "PRODUCT":
            guard !numbers.isEmpty else { return .number(0) }
            return .number(numbers.reduce(1, *))
        case "ABS":
            guard let n = numbers.first else { return .error("#VALUE!") }
            return .number(abs(n))
        case "INT":
            guard let n = numbers.first else { return .error("#VALUE!") }
            return .number(floor(n))
        case "SIGN":
            guard let n = numbers.first else { return .error("#VALUE!") }
            return .number(n > 0 ? 1 : (n < 0 ? -1 : 0))
        case "ROUND":
            guard let n = numbers.first else { return .error("#VALUE!") }
            let digits = numbers.count > 1 ? Int(numbers[1]) : 0
            let p = pow(10.0, Double(digits))
            return .number((n * p).rounded() / p)
        default:
            return .error("#NAME?")
        }
    }

    private func directionalCoords(_ dir: String, origin: CellCoord, table: TableData) -> [CellCoord] {
        switch dir {
        case "ABOVE":
            let startRow = table.hasHeaderRow ? 1 : 0
            guard origin.row > startRow else { return [] }
            return (startRow..<origin.row).map { CellCoord(row: $0, col: origin.col) }
        case "BELOW":
            guard origin.row + 1 < table.cells.count else { return [] }
            return ((origin.row + 1)..<table.cells.count).map { CellCoord(row: $0, col: origin.col) }
        case "LEFT":
            let startCol = table.hasHeaderColumn ? 1 : 0
            guard origin.col > startCol else { return [] }
            return (startCol..<origin.col).map { CellCoord(row: origin.row, col: $0) }
        case "RIGHT":
            let cols = table.cells.first?.count ?? 0
            guard origin.col + 1 < cols else { return [] }
            return ((origin.col + 1)..<cols).map { CellCoord(row: origin.row, col: $0) }
        default:
            return []
        }
    }

    private func applyBinary(_ op: String, _ lhs: EvalValue, _ rhs: EvalValue) -> EvalValue {
        if case .error(let e) = lhs { return .error(e) }
        if case .error(let e) = rhs { return .error(e) }
        guard let a = numericCoerce(lhs), let b = numericCoerce(rhs) else {
            return .error("#VALUE!")
        }
        switch op {
        case "+": return .number(a + b)
        case "-": return .number(a - b)
        case "*": return .number(a * b)
        case "/":
            if b == 0 { return a == 0 ? .error("#VALUE!") : .error("#DIV/0!") }
            return .number(a / b)
        default:
            return .error("#ERROR!")
        }
    }

    private func numericCoerce(_ value: EvalValue) -> Double? {
        switch value {
        case .number(let n): return n
        case .text(let s):
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? 0.0 : Double(t)
        case .error: return nil
        }
    }

    private func parseCellRef(_ ident: String) -> CellCoord? {
        var letters = ""
        var digits = ""
        for ch in ident {
            if ch.isLetter && digits.isEmpty {
                letters.append(ch)
            } else if ch.isNumber {
                digits.append(ch)
            } else {
                return nil
            }
        }
        guard !letters.isEmpty, !digits.isEmpty, let row1 = Int(digits), row1 >= 1 else { return nil }
        var col = 0
        for ch in letters.unicodeScalars {
            col = col * 26 + Int(ch.value - 64)
        }
        return CellCoord(row: row1 - 1, col: col - 1)
    }

    private enum Token {
        case number(Double)
        case ident(String)
        case op(String)
        case lparen, rparen, comma, colon
    }

    private func tokenize(_ expr: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(expr)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch.isWhitespace { i += 1; continue }
            if ch.isNumber || (ch == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                var s = ""
                while i < chars.count && (chars[i].isNumber || chars[i] == ".") {
                    s.append(chars[i]); i += 1
                }
                if let n = Double(s) { tokens.append(.number(n)) }
                continue
            }
            if ch.isLetter || ch == "_" {
                var s = ""
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                    s.append(chars[i]); i += 1
                }
                tokens.append(.ident(s))
                continue
            }
            switch ch {
            case "+", "-", "*", "/": tokens.append(.op(String(ch)))
            case "(": tokens.append(.lparen)
            case ")": tokens.append(.rparen)
            case ",": tokens.append(.comma)
            case ":": tokens.append(.colon)
            default: break
            }
            i += 1
        }
        return tokens
    }

    private func formatResult(_ value: EvalValue, format: TableCellFormat, isFormula: Bool) -> EvaluatedTableCell {
        switch value {
        case .error(let code):
            return EvaluatedTableCell(displayText: code, numericValue: nil, error: code)
        case .text(let s):
            return EvaluatedTableCell(displayText: s)
        case .number(let n):
            guard isFormula || format.kind != .text else {
                let clean = n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int64(n)) : String(n)
                return EvaluatedTableCell(displayText: clean, numericValue: n)
            }
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.maximumFractionDigits = format.precision
            formatter.minimumFractionDigits = (format.kind == .text) ? 0 : format.precision
            switch format.kind {
            case .text:
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 5
            case .number:
                formatter.numberStyle = .decimal
            case .percentage:
                formatter.numberStyle = .percent
            case .currency:
                formatter.numberStyle = .currency
                formatter.currencyCode = format.currencyCode
            }
            let rendered = formatter.string(from: NSNumber(value: n)) ?? String(n)
            return EvaluatedTableCell(displayText: rendered, numericValue: n)
        }
    }
}
