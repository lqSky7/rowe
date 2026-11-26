import Foundation

public enum SyntaxTokenKind: String, Sendable {
    case keyword
    case typeName
    case string
    case number
    case comment
    case attribute
    case functionCall
}

public struct SyntaxToken: Sendable, Hashable {
    public let range: NSRange
    public let kind: SyntaxTokenKind

    public init(range: NSRange, kind: SyntaxTokenKind) {
        self.range = range
        self.kind = kind
    }
}

/// Lightweight cross-platform code syntax tokenizer & rough language detector
/// powering pastel syntax highlighting on both macOS and iOS.
public enum RoweSyntaxHighlighter {
    public static let supportedLanguages: [String] = [
        "auto", "swift", "python", "go", "javascript", "typescript", "rust", "c", "json", "sql", "bash"
    ]

    /// Roughly detects the programming language from code content when set to "auto" or empty.
    public static func detectLanguage(for code: String, hint: String) -> String {
        let normalized = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !normalized.isEmpty && normalized != "auto" && normalized != "plain" && normalized != "text" {
            return normalized
        }
        let sample = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if sample.isEmpty { return "swift" }
        if (sample.hasPrefix("{") || sample.hasPrefix("[")) && sample.contains("\":") { return "json" }
        if sample.contains("SELECT ") || sample.contains("select ") || sample.contains("CREATE TABLE") { return "sql" }
        if sample.contains("package ") && sample.contains("func ") { return "go" }
        if sample.contains("def ") && sample.contains(":") { return "python" }
        if sample.contains("actor ") || sample.contains("@MainActor") || sample.contains("guard let ") || sample.contains("some View") { return "swift" }
        if sample.contains("fn ") && (sample.contains("let mut ") || sample.contains("impl ")) { return "rust" }
        if sample.contains("interface ") || sample.contains(": string") || sample.contains(": number") { return "typescript" }
        if sample.contains("const ") || sample.contains("function ") || sample.contains("=>") { return "javascript" }
        if sample.contains("#!/bin/") || sample.contains("echo ") { return "bash" }
        if sample.contains("#include") { return "c" }
        return "swift"
    }

    public static func tokenize(_ code: String, language: String) -> [SyntaxToken] {
        let ns = code as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        guard fullRange.length > 0 else { return [] }

        let lang = detectLanguage(for: code, hint: language)
        var tokens: [SyntaxToken] = []
        var occupied = IndexSet()

        func claim(_ range: NSRange, kind: SyntaxTokenKind) {
            guard range.location >= 0, range.length > 0, range.location + range.length <= ns.length else { return }
            let span = range.location..<(range.location + range.length)
            if occupied.intersects(integersIn: span) { return }
            occupied.insert(integersIn: span)
            tokens.append(SyntaxToken(range: range, kind: kind))
        }

        func applyRegex(_ pattern: String, options: NSRegularExpression.Options = [], group: Int = 0, kind: SyntaxTokenKind) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in regex.matches(in: code, range: fullRange) {
                guard group < match.numberOfRanges else { continue }
                claim(match.range(at: group), kind: kind)
            }
        }

        // 1. Comments (highest priority so keywords/strings inside comments stay muted)
        if lang == "python" || lang == "bash" {
            applyRegex(#"#[^\n]*"#, kind: .comment)
        } else if lang == "sql" {
            applyRegex(#"--[^\n]*"#, kind: .comment)
            applyRegex(#"/\*[\s\S]*?\*/"#, kind: .comment)
        } else {
            applyRegex(#"//[^\n]*"#, kind: .comment)
            applyRegex(#"/\*[\s\S]*?\*/"#, kind: .comment)
        }

        // 2. Strings (triple-quoted, double-quoted, single-quoted, backtick template)
        applyRegex(#"\"\"\"[\s\S]*?\"\"\""#, kind: .string)
        applyRegex(#"\"(?:\\.|[^\"\\\n])*\""#, kind: .string)
        applyRegex(#"'(?:\\.|[^'\\\n])*'"#, kind: .string)
        applyRegex(#"`(?:\\.|[^`\\])*`"#, kind: .string)

        // 3. Attributes / Decorators (@MainActor, @State, #include, #[derive])
        applyRegex(#"@[A-Za-z_][A-Za-z0-9_]*"#, kind: .attribute)
        if lang == "c" || lang == "rust" {
            applyRegex(#"#[A-Za-z_][A-Za-z0-9_]*"#, kind: .attribute)
        }

        // 4. Keywords
        let keywords = keywordList(for: lang)
        if !keywords.isEmpty {
            let kwPattern = "\\b(?:" + keywords.joined(separator: "|") + ")\\b"
            let opts: NSRegularExpression.Options = (lang == "sql") ? [.caseInsensitive] : []
            applyRegex(kwPattern, options: opts, kind: .keyword)
        }

        // 5. Numbers (hex, float, int)
        applyRegex(#"\b(?:0x[0-9a-fA-F_]+|\d+(?:\.\d+)?)\b"#, kind: .number)

        // 6. Function calls (identifier followed by '(')
        applyRegex(#"\b([a-z_][A-Za-z0-9_]*)\s*(?=\()"#, group: 1, kind: .functionCall)

        // 7. Type names (PascalCase identifiers, e.g. Duration, RoweSync, String)
        if lang != "json" && lang != "sql" {
            applyRegex(#"\b[A-Z][A-Za-z0-9_]*\b"#, kind: .typeName)
        }

        return tokens
    }

    private static func keywordList(for lang: String) -> [String] {
        switch lang {
        case "python":
            return ["def", "class", "return", "if", "elif", "else", "for", "while", "in", "not", "and", "or",
                    "import", "from", "as", "try", "except", "finally", "with", "yield", "async", "await",
                    "lambda", "pass", "break", "continue", "True", "False", "None", "self", "raise"]
        case "go":
            return ["package", "import", "func", "type", "struct", "interface", "return", "if", "else",
                    "for", "range", "switch", "case", "default", "go", "defer", "chan", "select",
                    "var", "const", "map", "make", "new", "nil", "true", "false", "error"]
        case "javascript", "typescript":
            return ["function", "const", "let", "var", "return", "if", "else", "for", "while", "switch",
                    "case", "break", "continue", "class", "extends", "new", "this", "import", "export",
                    "from", "default", "async", "await", "try", "catch", "finally", "throw", "typeof",
                    "interface", "type", "enum", "implements", "public", "private", "readonly", "true", "false", "null", "undefined"]
        case "rust":
            return ["fn", "let", "mut", "const", "struct", "enum", "impl", "trait", "for", "in", "while",
                    "loop", "if", "else", "match", "return", "pub", "use", "mod", "crate", "self", "Self",
                    "async", "await", "where", "move", "ref", "true", "false", "Some", "None", "Ok", "Err"]
        case "sql":
            return ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
                    "CREATE", "TABLE", "ALTER", "DROP", "JOIN", "LEFT", "RIGHT", "INNER", "ON", "GROUP",
                    "BY", "ORDER", "ASC", "DESC", "LIMIT", "AS", "AND", "OR", "NOT", "NULL", "PRIMARY", "KEY"]
        case "bash":
            return ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "case", "esac",
                    "function", "export", "local", "return", "echo", "exit", "true", "false"]
        case "json":
            return ["true", "false", "null"]
        default: // swift & c-like
            return ["actor", "func", "let", "var", "struct", "class", "enum", "protocol", "extension",
                    "import", "return", "if", "else", "guard", "switch", "case", "default", "for", "in",
                    "while", "repeat", "break", "continue", "try", "catch", "throw", "throws", "async",
                    "await", "public", "private", "internal", "fileprivate", "open", "static", "final",
                    "override", "init", "deinit", "self", "Self", "nil", "true", "false", "some", "any",
                    "where", "defer", "weak", "unowned", "mutating", "nonisolated", "Sendable", "void", "int", "char"]
        }
    }
}
