import SwiftUI

/// Native SwiftUI LaTeX math parser and typesetter (fractions, radicals with overbar,
/// superscripts/subscripts, large operators, Greek letters, and upright `\text{...}`).
/// Zero external dependencies — works identically on macOS and iOS.
public struct RoweMathView: View {
    public let latex: String
    public let fontSize: CGFloat
    public let inkColor: Color

    public init(latex: String, fontSize: CGFloat = 15, inkColor: Color = .primary) {
        self.latex = latex
        self.fontSize = fontSize
        self.inkColor = inkColor
    }

    public var body: some View {
        let ast = LaTeXMathParser(latex).parse()
        MathNodeView(node: ast, fontSize: fontSize, inkColor: inkColor)
            .fixedSize(horizontal: true, vertical: true)
    }
}

// MARK: - AST

private indirect enum MathNode {
    case empty
    case row([MathNode])
    case text(String, bold: Bool)
    case variable(String)
    case number(String)
    case op(String)
    case symbol(String)
    case fraction(num: MathNode, den: MathNode)
    case sqrt(index: MathNode?, radicand: MathNode)
    case script(base: MathNode, sup: MathNode?, sub: MathNode?)
    case largeOp(symbol: String, lower: MathNode?, upper: MathNode?)
    case accent(mark: String, body: MathNode)
}

// MARK: - Recursive-Descent LaTeX Parser

private final class LaTeXMathParser {
    private let chars: [Character]
    private var idx: Int = 0

    init(_ input: String) {
        self.chars = Array(input)
    }

    func parse() -> MathNode {
        parseSequence(stopAt: nil)
    }

    private var isAtEnd: Bool { idx >= chars.count }
    private func peek() -> Character? { isAtEnd ? nil : chars[idx] }
    private func advance() -> Character {
        let c = chars[idx]
        idx += 1
        return c
    }

    private func skipWhitespace() {
        while let c = peek(), c.isWhitespace { _ = advance() }
    }

    private func parseSequence(stopAt: Character?) -> MathNode {
        var nodes: [MathNode] = []
        while !isAtEnd {
            skipWhitespace()
            guard let c = peek() else { break }
            if let stop = stopAt, c == stop {
                _ = advance()
                break
            }
            if let node = parseScriptedAtom() {
                nodes.append(node)
            }
        }
        if nodes.isEmpty { return .empty }
        if nodes.count == 1 { return nodes[0] }
        return .row(nodes)
    }

    private func parseScriptedAtom() -> MathNode? {
        guard var base = parseAtom() else { return nil }
        var sup: MathNode?
        var sub: MathNode?

        while true {
            skipWhitespace()
            guard let c = peek(), c == "^" || c == "_" else { break }
            _ = advance()
            skipWhitespace()
            let arg = parseGroupOrAtom()
            if c == "^" {
                sup = arg
            } else {
                sub = arg
            }
        }

        if sup != nil || sub != nil {
            if case .largeOp(let sym, nil, nil) = base {
                return .largeOp(symbol: sym, lower: sub, upper: sup)
            }
            base = .script(base: base, sup: sup, sub: sub)
        }
        return base
    }

    private func parseGroupOrAtom() -> MathNode {
        skipWhitespace()
        if peek() == "{" {
            _ = advance()
            return parseSequence(stopAt: "}")
        }
        return parseAtom() ?? .empty
    }

    private func parseOptionalBracket() -> MathNode? {
        skipWhitespace()
        guard peek() == "[" else { return nil }
        _ = advance()
        return parseSequence(stopAt: "]")
    }

    private func parseRawBraceText() -> String {
        skipWhitespace()
        guard peek() == "{" else {
            return isAtEnd ? "" : String(advance())
        }
        _ = advance()
        var depth = 1
        var out = ""
        while !isAtEnd && depth > 0 {
            let c = advance()
            if c == "{" {
                depth += 1
                out.append(c)
            } else if c == "}" {
                depth -= 1
                if depth > 0 { out.append(c) }
            } else {
                out.append(c)
            }
        }
        return out
    }

    private func parseAtom() -> MathNode? {
        skipWhitespace()
        guard let c = peek() else { return nil }

        if c == "{" {
            _ = advance()
            return parseSequence(stopAt: "}")
        }
        if c == "}" {
            _ = advance()
            return nil
        }
        if c == "\\" {
            return parseCommand()
        }
        if c.isNumber {
            var num = ""
            while let ch = peek(), ch.isNumber || ch == "." {
                num.append(advance())
            }
            return .number(num)
        }
        if c.isLetter {
            _ = advance()
            return .variable(String(c))
        }
        _ = advance()
        switch c {
        case "+", "=", "<", ">":
            return .op(String(c))
        case "-":
            return .op("−")
        case "/":
            return .op("/")
        case ",":
            return .symbol(", ")
        case ";":
            return .symbol("; ")
        case ":":
            return .op(":")
        default:
            return .symbol(String(c))
        }
    }

    private func parseCommand() -> MathNode? {
        _ = advance() // consume '\'
        guard let first = peek() else { return nil }

        // Single-character escaped symbols: \{ \} \| \, \; \! \\
        if !first.isLetter {
            _ = advance()
            switch first {
            case "{": return .symbol("{")
            case "}": return .symbol("}")
            case "|": return .symbol("‖")
            case ",": return .symbol(" ")
            case ";": return .symbol(" ")
            case " ": return .symbol(" ")
            case "!": return .empty
            default: return .symbol(String(first))
            }
        }

        var cmd = ""
        while let ch = peek(), ch.isLetter {
            cmd.append(advance())
        }

        switch cmd {
        case "frac", "dfrac", "tfrac":
            let num = parseGroupOrAtom()
            let den = parseGroupOrAtom()
            return .fraction(num: num, den: den)
        case "sqrt":
            let index = parseOptionalBracket()
            let rad = parseGroupOrAtom()
            return .sqrt(index: index, radicand: rad)
        case "text", "mathrm", "operatorname", "textrm":
            return .text(parseRawBraceText(), bold: false)
        case "mathbf", "textbf", "bm":
            return .text(parseRawBraceText(), bold: true)
        case "mathbb":
            let raw = parseRawBraceText()
            return .text(Self.blackboardMap[raw] ?? raw, bold: false)
        case "hat":
            return .accent(mark: "ˆ", body: parseGroupOrAtom())
        case "bar", "overline":
            return .accent(mark: "¯", body: parseGroupOrAtom())
        case "vec":
            return .accent(mark: "→", body: parseGroupOrAtom())
        case "tilde":
            return .accent(mark: "˜", body: parseGroupOrAtom())
        case "left", "right":
            skipWhitespace()
            if peek() == "." {
                _ = advance()
                return .empty
            }
            if peek() == "\\" {
                return parseCommand()
            }
            if let delim = peek() {
                _ = advance()
                return .symbol(String(delim))
            }
            return .empty
        case "sum": return .largeOp(symbol: "∑", lower: nil, upper: nil)
        case "prod": return .largeOp(symbol: "∏", lower: nil, upper: nil)
        case "int": return .largeOp(symbol: "∫", lower: nil, upper: nil)
        case "lim": return .largeOp(symbol: "lim", lower: nil, upper: nil)
        case "sin", "cos", "tan", "log", "ln", "exp", "max", "min", "arg", "det", "softmax", "Attn":
            return .text(cmd, bold: false)
        case "quad": return .symbol("  ")
        case "qquad": return .symbol("    ")
        default:
            if let op = Self.operatorMap[cmd] { return .op(op) }
            if let sym = Self.symbolMap[cmd] { return .symbol(sym) }
            return .text(cmd, bold: false)
        }
    }

    private static let blackboardMap: [String: String] = [
        "R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ", "E": "𝔼", "P": "ℙ"
    ]

    private static let operatorMap: [String: String] = [
        "times": "×", "cdot": "·", "pm": "±", "mp": "∓", "div": "÷",
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠",
        "approx": "≈", "equiv": "≡", "sim": "∼", "propto": "∝",
        "in": "∈", "notin": "∉", "subset": "⊂", "subseteq": "⊆", "supset": "⊃",
        "cup": "∪", "cap": "∩", "to": "→", "rightarrow": "→", "leftarrow": "←",
        "Rightarrow": "⇒", "Leftarrow": "⇐", "iff": "⇔", "mapsto": "↦", "circ": "∘"
    ]

    private static let symbolMap: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ϵ", "varepsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ",
        "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "ϕ", "varphi": "φ", "chi": "χ",
        "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π",
        "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        "infty": "∞", "partial": "∂", "nabla": "∇", "forall": "∀", "exists": "∃",
        "emptyset": "∅", "dots": "…", "ldots": "…", "cdots": "⋯", "vdots": "⋮",
        "langle": "⟨", "rangle": "⟩", "ell": "ℓ", "hbar": "ℏ", "top": "⊤", "bot": "⊥"
    ]
}

// MARK: - SwiftUI Recursive Typesetter

private struct MathNodeView: View {
    let node: MathNode
    let fontSize: CGFloat
    let inkColor: Color

    var body: some View {
        switch node {
        case .empty:
            EmptyView()

        case .row(let items):
            HStack(alignment: .center, spacing: 1) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, child in
                    MathNodeView(node: child, fontSize: fontSize, inkColor: inkColor)
                }
            }

        case .text(let str, let bold):
            Text(str)
                .font(.system(size: fontSize, weight: bold ? .semibold : .regular, design: .serif))
                .foregroundStyle(inkColor)

        case .variable(let str):
            Text(str)
                .font(.system(size: fontSize, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(inkColor)

        case .number(let str):
            Text(str)
                .font(.system(size: fontSize, weight: .regular, design: .serif))
                .foregroundStyle(inkColor)

        case .op(let str):
            Text(str)
                .font(.system(size: fontSize, weight: .regular, design: .serif))
                .foregroundStyle(inkColor.opacity(0.9))
                .padding(.horizontal, str == "/" ? 2 : 3.5)

        case .symbol(let str):
            Text(str)
                .font(.system(size: fontSize, weight: .regular, design: .serif))
                .foregroundStyle(inkColor)

        case .fraction(let num, let den):
            VStack(spacing: 1.5) {
                MathNodeView(node: num, fontSize: max(10, fontSize * 0.84), inkColor: inkColor)
                    .padding(.horizontal, 3)
                Rectangle()
                    .fill(inkColor.opacity(0.75))
                    .frame(height: 1)
                MathNodeView(node: den, fontSize: max(10, fontSize * 0.84), inkColor: inkColor)
                    .padding(.horizontal, 3)
            }
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 2)

        case .sqrt(let index, let radicand):
            HStack(alignment: .center, spacing: 0) {
                if let index {
                    MathNodeView(node: index, fontSize: max(8.5, fontSize * 0.58), inkColor: inkColor)
                        .offset(x: 3, y: -fontSize * 0.34)
                }
                Text("√")
                    .font(.system(size: fontSize * 1.16, weight: .light, design: .serif))
                    .foregroundStyle(inkColor)
                MathNodeView(node: radicand, fontSize: fontSize, inkColor: inkColor)
                    .padding(.horizontal, 2.5)
                    .padding(.top, 1.5)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(inkColor.opacity(0.8))
                            .frame(height: 1)
                    }
            }
            .padding(.horizontal, 1.5)

        case .script(let base, let sup, let sub):
            HStack(alignment: .center, spacing: 0.5) {
                MathNodeView(node: base, fontSize: fontSize, inkColor: inkColor)
                VStack(alignment: .leading, spacing: 0) {
                    if let sup {
                        MathNodeView(node: sup, fontSize: max(9, fontSize * 0.68), inkColor: inkColor)
                            .offset(y: sub == nil ? -fontSize * 0.28 : -1)
                    }
                    if let sub {
                        MathNodeView(node: sub, fontSize: max(9, fontSize * 0.68), inkColor: inkColor)
                            .offset(y: sup == nil ? fontSize * 0.28 : 1)
                    }
                }
            }

        case .largeOp(let symbol, let lower, let upper):
            VStack(spacing: 0) {
                if let upper {
                    MathNodeView(node: upper, fontSize: max(9, fontSize * 0.64), inkColor: inkColor)
                }
                Text(symbol)
                    .font(.system(size: symbol == "lim" ? fontSize * 0.95 : fontSize * 1.38, weight: .regular, design: .serif))
                    .foregroundStyle(inkColor)
                if let lower {
                    MathNodeView(node: lower, fontSize: max(9, fontSize * 0.64), inkColor: inkColor)
                }
            }
            .padding(.horizontal, 2)

        case .accent(let mark, let body):
            VStack(spacing: -fontSize * 0.32) {
                Text(mark)
                    .font(.system(size: fontSize * 0.85, weight: .regular, design: .serif))
                    .foregroundStyle(inkColor)
                MathNodeView(node: body, fontSize: fontSize, inkColor: inkColor)
            }
        }
    }
}
