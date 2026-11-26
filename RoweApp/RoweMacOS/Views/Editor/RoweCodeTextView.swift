import AppKit
import SwiftUI
import RoweCore

/// Native AppKit monospaced code editor with live pastel syntax highlighting
/// that adapts legibly to both light paper and dark paper.
struct RoweCodeTextView: NSViewRepresentable {
    let code: String
    let language: String
    let isLightPaper: Bool
    let baseInkColor: NSColor
    var onCodeChange: (String) -> Void
    var onFocusGained: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CodeNSTextView {
        let tv = CodeNSTextView()
        tv.delegate = context.coordinator
        tv.drawsBackground = false
        tv.isRichText = true
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.textContainerInset = NSSize(width: 2, height: 4)
        tv.textContainer?.lineFragmentPadding = 2
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.required, for: .vertical)

        context.coordinator.syncFromModel(tv, force: true)
        return tv
    }

    func updateNSView(_ tv: CodeNSTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncFromModel(tv, force: false)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RoweCodeTextView
        private var isSyncing = false
        private var lastSignature = ""

        init(parent: RoweCodeTextView) {
            self.parent = parent
        }

        private var signature: String {
            "\(parent.code.hashValue)|\(parent.language)|\(parent.isLightPaper)|\(parent.baseInkColor.description)"
        }

        func syncFromModel(_ tv: CodeNSTextView, force: Bool) {
            let sig = signature
            guard force || sig != lastSignature else { return }
            lastSignature = sig
            isSyncing = true
            defer { isSyncing = false }

            let savedRange = tv.selectedRange()
            let attributed = Self.highlightedAttributedString(
                code: parent.code,
                language: parent.language,
                isLightPaper: parent.isLightPaper,
                baseInk: parent.baseInkColor
            )
            tv.textStorage?.setAttributedString(attributed)
            tv.typingAttributes = Self.baseAttributes(baseInk: parent.baseInkColor)
            tv.insertionPointColor = parent.baseInkColor

            let maxLen = (parent.code as NSString).length
            let loc = min(savedRange.location, maxLen)
            let len = min(savedRange.length, max(0, maxLen - loc))
            tv.setSelectedRange(NSRange(location: loc, length: len))
            tv.invalidateIntrinsicContentSize()
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusGained()
        }

        func textDidChange(_ notification: Notification) {
            guard !isSyncing, let tv = notification.object as? CodeNSTextView else { return }
            let newCode = tv.string
            parent.onCodeChange(newCode)

            // Re-apply pastel highlights live while preserving caret position
            let saved = tv.selectedRange()
            isSyncing = true
            let attr = Self.highlightedAttributedString(
                code: newCode,
                language: parent.language,
                isLightPaper: parent.isLightPaper,
                baseInk: parent.baseInkColor
            )
            tv.textStorage?.setAttributedString(attr)
            tv.setSelectedRange(saved)
            tv.typingAttributes = Self.baseAttributes(baseInk: parent.baseInkColor)
            lastSignature = "\(newCode.hashValue)|\(parent.language)|\(parent.isLightPaper)|\(parent.baseInkColor.description)"
            isSyncing = false
            tv.invalidateIntrinsicContentSize()
        }

        private static func baseAttributes(baseInk: NSColor) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = 1.32
            return [
                .font: NSFont.monospacedSystemFont(ofSize: 12.8, weight: .regular),
                .foregroundColor: baseInk,
                .paragraphStyle: paragraph
            ]
        }

        /// Pastel syntax palette tuned for legibility on both light paper and dark paper.
        private static func pastelColor(for kind: SyntaxTokenKind, isLightPaper: Bool) -> NSColor {
            if isLightPaper {
                switch kind {
                case .keyword: return NSColor(hex: "#7A5FA8")      // soft pastel lavender-plum
                case .typeName: return NSColor(hex: "#3E7699")     // soft pastel slate-sky
                case .string: return NSColor(hex: "#448264")       // soft pastel sage
                case .number: return NSColor(hex: "#B56B45")       // soft pastel peach-terracotta
                case .comment: return NSColor(hex: "#7D8590")      // soft cool grey
                case .attribute: return NSColor(hex: "#B05B78")    // soft pastel dusty rose
                case .functionCall: return NSColor(hex: "#4B7A8C") // soft pastel teal-blue
                }
            } else {
                switch kind {
                case .keyword: return NSColor(hex: "#C8B8F4")      // luminous pastel lavender
                case .typeName: return NSColor(hex: "#A5D0F5")     // luminous pastel sky blue
                case .string: return NSColor(hex: "#AEE2C6")       // luminous pastel mint-sage
                case .number: return NSColor(hex: "#F6C29F")       // luminous pastel peach
                case .comment: return NSColor(hex: "#8E99A8")      // muted pastel grey-blue
                case .attribute: return NSColor(hex: "#F2B1C8")    // luminous pastel blush rose
                case .functionCall: return NSColor(hex: "#B2DDE4") // luminous pastel aqua
                }
            }
        }

        private static func highlightedAttributedString(
            code: String,
            language: String,
            isLightPaper: Bool,
            baseInk: NSColor
        ) -> NSAttributedString {
            let result = NSMutableAttributedString(string: code, attributes: baseAttributes(baseInk: baseInk))
            let tokens = RoweSyntaxHighlighter.tokenize(code, language: language)
            let italicFont = NSFontManager.shared.convert(
                NSFont.monospacedSystemFont(ofSize: 12.8, weight: .regular),
                toHaveTrait: .italicFontMask
            )
            let mediumFont = NSFont.monospacedSystemFont(ofSize: 12.8, weight: .medium)

            for token in tokens {
                let color = pastelColor(for: token.kind, isLightPaper: isLightPaper)
                result.addAttribute(.foregroundColor, value: color, range: token.range)
                if token.kind == .comment {
                    result.addAttribute(.font, value: italicFont, range: token.range)
                } else if token.kind == .keyword {
                    result.addAttribute(.font, value: mediumFont, range: token.range)
                }
            }
            return result
        }
    }
}

final class CodeNSTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let lm = layoutManager, let tc = textContainer else {
            return super.intrinsicContentSize
        }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(58, ceil(used.height + textContainerInset.height * 2 + 4)))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(newSize.width - frame.size.width) > 0.5
        super.setFrameSize(newSize)
        if changed { invalidateIntrinsicContentSize() }
    }
}
