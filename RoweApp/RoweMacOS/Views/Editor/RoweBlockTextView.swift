import AppKit
import SwiftUI
import RoweCore

/// Native AppKit TextKit block editor implementing Craft's v2-editor-spec:
/// - UTF-16 inline attributed runs (bold, italic, strike, code, highlight, link, #tag)
/// - Live Markdown prefix triggers (# , ## , ### , - , * , + , [] , [x] , > , 1. , ---, ```)
/// - Live inline delimiter triggers (**bold**, *italic*, `code`, ~~strike~~, ==highlight==, [label](url))
/// - Auto-pairing selection wrap, Shift+Return soft break, Return block split
/// - Offset-0 Backspace 5-step precedence & end Forward Delete
/// - First/last visual line Arrow Up/Down jumping with sticky desiredCaretX
/// - Cmd+A two-stage escalation & Esc escalation to blockSelection
struct RoweBlockTextView: NSViewRepresentable {
    let block: Block
    let fontFamily: FontFamily
    let textColor: NSColor
    let isStruckCompletedTask: Bool
    let isActiveBlock: Bool
    let caretRequest: BlockCaretRequest?

    var onContentChange: (_ content: String, _ runs: [TextRunAttributes], _ caretOffset: Int) -> Void
    var onSelectionRangeChange: (_ utf16Offset: Int, _ utf16Length: Int) -> Void
    var onFocusGained: () -> Void
    var onReturnSplit: (_ utf16Offset: Int) -> Void
    var onCmdReturn: () -> Void
    var onBackspaceAtStart: () -> Void
    var onForwardDeleteAtEnd: () -> Void
    var onIndent: (_ delta: Int) -> Void
    var onMoveVertical: (_ direction: Int, _ desiredX: Double, _ extendSelection: Bool) -> Void
    var onEscalateSelectAll: () -> Void
    var onEscapeToBlockSelection: () -> Void
    var onOpenSlashMenu: (_ caretRectInWindow: CGRect?) -> Void
    var onApplyPrefixTransform: (_ transform: BlockPrefixTransform) -> Void
    var onPasteMultiline: (_ utf16Offset: Int, _ text: String) -> Void

    enum BlockPrefixTransform {
        case textStyle(BlockTextStyle)
        case listStyle(BlockListStyle, checked: Bool, number: Int?)
        case decoration(BlockDecoration)
        case separator
        case codeBlock
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> RoweNSTextView {
        let textView = RoweNSTextView()
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = false // Undo managed at document-snapshot level by WorkspaceStore
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 2
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)

        context.coordinator.syncFromModel(textView: textView, block: block, force: true)
        return textView
    }

    func updateNSView(_ textView: RoweNSTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncFromModel(textView: textView, block: block, force: false)

        if let req = caretRequest, req.blockId == block.id, context.coordinator.lastHandledRequestId != req.id {
            context.coordinator.lastHandledRequestId = req.id
            DispatchQueue.main.async {
                context.coordinator.applyCaretRequest(req, to: textView)
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RoweBlockTextView
        var isApplyingModelSync = false
        var lastHandledRequestId: UUID?
        var lastRenderedSignature: String = ""
        var lastStruckState: Bool
        var strikeSweepTask: Task<Void, Never>?
        var stickyDesiredX: CGFloat?

        init(parent: RoweBlockTextView) {
            self.parent = parent
            self.lastStruckState = parent.isStruckCompletedTask
        }

        private func styleSignature(for block: Block) -> String {
            "\(block.content.hashValue)|\(block.runs.hashValue)|\(block.textStyle.rawValue)|\(block.alignment.rawValue)|\(block.isBold)|\(block.isItalic)|\(block.isStrikethrough)|\(block.isInlineCode)|\(parent.fontFamily.rawValue)|\(parent.textColor.description)|\(parent.isStruckCompletedTask)"
        }

        func syncFromModel(textView: RoweNSTextView, block: Block, force: Bool) {
            let sig = styleSignature(for: block)
            guard force || sig != lastRenderedSignature else { return }
            lastRenderedSignature = sig

            let strikeChanged = !force && (lastStruckState != parent.isStruckCompletedTask)
            lastStruckState = parent.isStruckCompletedTask

            isApplyingModelSync = true
            defer { isApplyingModelSync = false }

            let savedRange = textView.selectedRange()
            let attributed = buildAttributedString(for: block, strikeFraction: strikeChanged ? (parent.isStruckCompletedTask ? 0.0 : 1.0) : (parent.isStruckCompletedTask ? 1.0 : 0.0))
            textView.textStorage?.setAttributedString(attributed)

            if strikeChanged {
                animateStrikeSweep(in: textView, block: block, to: parent.isStruckCompletedTask ? 1.0 : 0.0)
            }
            textView.typingAttributes = baseTypingAttributes(for: block)
            textView.insertionPointColor = parent.textColor

            let maxLen = (block.content as NSString).length
            let clampedLoc = min(savedRange.location, maxLen)
            let clampedLen = min(savedRange.length, max(0, maxLen - clampedLoc))
            textView.setSelectedRange(NSRange(location: clampedLoc, length: clampedLen))
            textView.invalidateIntrinsicContentSize()
        }

        func applyCaretRequest(_ req: BlockCaretRequest, to textView: RoweNSTextView) {
            textView.window?.makeFirstResponder(textView)
            let len = (textView.string as NSString).length
            if req.selectAll {
                textView.setSelectedRange(NSRange(location: 0, length: len))
            } else if let offset = req.utf16Offset {
                let clamped = max(0, min(offset, len))
                textView.setSelectedRange(NSRange(location: clamped, length: 0))
                stickyDesiredX = nil
            } else if let desiredX = req.desiredX, let lm = textView.layoutManager, let tc = textView.textContainer {
                lm.ensureLayout(for: tc)
                let used = lm.usedRect(for: tc)
                let targetY: CGFloat = req.fromBottom ? max(2, used.height - 6) : 6
                let pt = NSPoint(x: max(0, CGFloat(desiredX)), y: targetY)
                let idx = textView.characterIndexForInsertion(at: pt)
                textView.setSelectedRange(NSRange(location: min(idx, len), length: 0))
                stickyDesiredX = CGFloat(desiredX)
            } else {
                textView.setSelectedRange(NSRange(location: len, length: 0))
            }
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func baseTypingAttributes(for block: Block) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = block.textStyle == .body ? 1.25 : 1.12
            switch block.alignment {
            case .leading: paragraph.alignment = .left
            case .center: paragraph.alignment = .center
            case .trailing: paragraph.alignment = .right
            case .justified: paragraph.alignment = .justified
            }

            let font = CraftTheme.nsFont(
                for: block.textStyle,
                family: parent.fontFamily,
                isBold: block.isBold,
                isItalic: block.isItalic,
                isCode: block.isInlineCode
            )
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: parent.isStruckCompletedTask ? parent.textColor.withAlphaComponent(0.5) : parent.textColor,
                .paragraphStyle: paragraph
            ]
            if block.isStrikethrough {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if block.isInlineCode {
                attrs[.backgroundColor] = NSColor.labelColor.withAlphaComponent(0.08)
            }
            return attrs
        }

        private func animateStrikeSweep(in textView: RoweNSTextView, block: Block, to target: Double) {
            strikeSweepTask?.cancel()
            let start = target == 1.0 ? 0.0 : 1.0
            let steps = 14
            strikeSweepTask = Task { @MainActor [weak self, weak textView] in
                for step in 1...steps {
                    try? await Task.sleep(nanoseconds: 15_000_000)
                    guard !Task.isCancelled, let self, let tv = textView else { return }
                    let t = Double(step) / Double(steps)
                    let eased = 1.0 - pow(1.0 - t, 3.0)
                    let frac = start + (target - start) * eased
                    let saved = tv.selectedRange()
                    self.isApplyingModelSync = true
                    tv.textStorage?.setAttributedString(self.buildAttributedString(for: block, strikeFraction: frac))
                    tv.setSelectedRange(saved)
                    self.isApplyingModelSync = false
                }
            }
        }

        func buildAttributedString(for block: Block, strikeFraction: Double = 1.0) -> NSAttributedString {
            let baseAttrs = baseTypingAttributes(for: block)
            let result = NSMutableAttributedString(string: block.content, attributes: baseAttrs)
            let utf16Len = result.length

            if utf16Len > 0 && strikeFraction > 0 && (parent.isStruckCompletedTask || strikeFraction < 1.0) {
                let struckLen = min(utf16Len, max(0, Int((Double(utf16Len) * strikeFraction).rounded())))
                if struckLen > 0 {
                    result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: struckLen))
                }
            }

            for run in block.runs {
                let loc = max(0, min(run.location, utf16Len))
                let len = max(0, min(run.length, utf16Len - loc))
                guard len > 0 else { continue }
                let range = NSRange(location: loc, length: len)

                let runFont = CraftTheme.nsFont(
                    for: block.textStyle,
                    family: parent.fontFamily,
                    isBold: block.isBold || run.isBold,
                    isItalic: block.isItalic || run.isItalic,
                    isCode: block.isInlineCode || run.isCode
                )
                result.addAttribute(.font, value: runFont, range: range)

                if run.isStrikethrough {
                    result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                }
                if run.isCode {
                    result.addAttribute(.backgroundColor, value: NSColor.labelColor.withAlphaComponent(0.09), range: range)
                }
                if let hlHex = run.highlightColor {
                    result.addAttribute(.backgroundColor, value: NSColor(hex: hlHex).withAlphaComponent(0.32), range: range)
                }
                if let colorHex = run.textColorHex {
                    result.addAttribute(.foregroundColor, value: NSColor(hex: colorHex), range: range)
                }
                if let urlStr = run.linkURL, let url = URL(string: urlStr) {
                    result.addAttribute(.link, value: url, range: range)
                    result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                }
            }

            // Live #tag highlighting matching Spec 01 §2.2
            if utf16Len > 1,
               let regex = try? NSRegularExpression(pattern: #"(?<!#)(?<=^|\s|\p{P})#([A-Za-z0-9_/\-]+)(?=\s|\p{P}|$)"#) {
                let matches = regex.matches(in: block.content, range: NSRange(location: 0, length: utf16Len))
                for m in matches {
                    result.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: m.range)
                    result.addAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.11), range: m.range)
                }
            }

            return result
        }

        // MARK: - NSTextViewDelegate

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusGained()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingModelSync, let tv = notification.object as? NSTextView else { return }
            let r = tv.selectedRange()
            parent.onSelectionRangeChange(r.location, r.length)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacement = replacementString else { return true }

            // Multi-line paste -> split into structured blocks in one undo step (Spec 04 §4.2)
            if replacement.count > 1 && replacement.contains("\n") {
                parent.onPasteMultiline(affectedCharRange.location, replacement)
                return false
            }

            // Auto-pairing wrap on non-empty selection (Spec 02 §3.3)
            if affectedCharRange.length > 0 && replacement.count == 1 {
                let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
                if let closing = pairs[replacement] {
                    let ns = textView.string as NSString
                    let selected = ns.substring(with: affectedCharRange)
                    let wrapped = replacement + selected + closing
                    let updated = ns.replacingCharacters(in: affectedCharRange, with: wrapped)
                    let adjustedRuns = adjustRunsForEdit(parent.block.runs, range: affectedCharRange, replacementUTF16Len: wrapped.utf16.count)
                    parent.onContentChange(updated, adjustedRuns, affectedCharRange.location + 1)
                    DispatchQueue.main.async {
                        textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: affectedCharRange.length))
                    }
                    return false
                }
            }

            // Block prefix triggers on Space (Spec 02 §3.1)
            if replacement == " " && affectedCharRange.length == 0 {
                let ns = textView.string as NSString
                let prefix = ns.substring(to: affectedCharRange.location)
                if let transform = matchBlockPrefix(prefix) {
                    let remainder = ns.substring(from: affectedCharRange.location)
                    let (_, shiftedRuns) = TextRunAttributes.split(parent.block.runs, at: affectedCharRange.location, totalLength: ns.length)
                    parent.onContentChange(remainder, shiftedRuns, 0)
                    parent.onApplyPrefixTransform(transform)
                    return false
                }
            }

            // "---" separator trigger (Spec 02 §3.1)
            if replacement == "-" && affectedCharRange.length == 0 {
                let ns = textView.string as NSString
                let candidate = ns.replacingCharacters(in: affectedCharRange, with: "-")
                if candidate == "---" {
                    parent.onContentChange("", [], 0)
                    parent.onApplyPrefixTransform(.separator)
                    return false
                }
            }

            // "```" code block trigger (Spec 02 §3.1)
            if replacement == "`" && affectedCharRange.length == 0 {
                let ns = textView.string as NSString
                let candidate = ns.replacingCharacters(in: affectedCharRange, with: "`")
                if candidate == "```" {
                    parent.onContentChange("", [], 0)
                    parent.onApplyPrefixTransform(.codeBlock)
                    return false
                }
            }

            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingModelSync, let tv = notification.object as? RoweNSTextView else { return }
            let newText = tv.string
            let caret = tv.selectedRange().location
            stickyDesiredX = nil

            // Check live inline markdown delimiters (Spec 02 §3.2)
            if let (transformedText, updatedRuns, newCaret) = applyInlineMarkdownIfMatched(text: newText, existingRuns: parent.block.runs, caretOffset: caret) {
                parent.onContentChange(transformedText, updatedRuns, newCaret)
                DispatchQueue.main.async {
                    tv.setSelectedRange(NSRange(location: newCaret, length: 0))
                    tv.typingAttributes = self.baseTypingAttributes(for: self.parent.block)
                }
            } else {
                let normalized = TextRunAttributes.normalize(parent.block.runs, utf16Length: newText.utf16.count)
                parent.onContentChange(newText, normalized, caret)
            }

            tv.invalidateIntrinsicContentSize()

            // Trigger Slash Menu if user typed '/' at offset 0 or right after whitespace (Spec 03 §1.2)
            if caret > 0 {
                let ns = newText as NSString
                if caret <= ns.length {
                    let prevChar = ns.substring(with: NSRange(location: caret - 1, length: 1))
                    if prevChar == "/" {
                        let isAtStart = (caret == 1)
                        let afterSpace = caret >= 2 && ns.substring(with: NSRange(location: caret - 2, length: 1)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        if isAtStart || afterSpace {
                            parent.onOpenSlashMenu(tv.caretRectInWindow())
                        }
                    }
                }
            }
        }

        // MARK: - Inline Formatting Shortcuts (Cmd+B / Cmd+I / Cmd+Shift+X / Cmd+E / Cmd+Shift+H)

        func toggleInlineStyle(_ kind: InlineFormatKind, in textView: NSTextView) {
            let sel = textView.selectedRange()
            guard sel.length > 0 else { return }
            var runs = parent.block.runs
            let hasAll = runs.contains { r in
                r.location <= sel.location && r.upperBound >= (sel.location + sel.length) && kind.isSet(in: r)
            }
            var newRun = TextRunAttributes(location: sel.location, length: sel.length)
            kind.apply(!hasAll, to: &newRun)
            if !hasAll {
                runs.append(newRun)
            } else {
                // Clear that flag over the selected range
                runs = runs.map { r in
                    var copy = r
                    if r.location < sel.location + sel.length && r.upperBound > sel.location {
                        kind.apply(false, to: &copy)
                    }
                    return copy
                }
            }
            let normalized = TextRunAttributes.normalize(runs, utf16Length: (textView.string as NSString).length)
            parent.onContentChange(textView.string, normalized, sel.location)
        }

        enum InlineFormatKind {
            case bold, italic, strikethrough, code, highlight

            func isSet(in run: TextRunAttributes) -> Bool {
                switch self {
                case .bold: run.isBold
                case .italic: run.isItalic
                case .strikethrough: run.isStrikethrough
                case .code: run.isCode
                case .highlight: run.highlightColor != nil
                }
            }

            func apply(_ enabled: Bool, to run: inout TextRunAttributes) {
                switch self {
                case .bold: run.isBold = enabled
                case .italic: run.isItalic = enabled
                case .strikethrough: run.isStrikethrough = enabled
                case .code: run.isCode = enabled
                case .highlight: run.highlightColor = enabled ? "#DFC370" : nil
                }
            }
        }

        // MARK: - Prefix & Inline Markdown Matching

        private func matchBlockPrefix(_ prefix: String) -> BlockPrefixTransform? {
            switch prefix {
            case "#": return .textStyle(.title)
            case "##": return .textStyle(.subtitle)
            case "###": return .textStyle(.heading)
            case "####": return .textStyle(.strong)
            case "-", "*": return .listStyle(.bullet, checked: false, number: nil)
            case "+": return .listStyle(.toggle, checked: false, number: nil)
            case "[]", "[ ]", "-[]", "- []", "- [ ]": return .listStyle(.todo, checked: false, number: nil)
            case "[x]", "[X]", "-[x]", "- [x]": return .listStyle(.todo, checked: true, number: nil)
            case ">", "|": return .decoration(.focus)
            default:
                if prefix.hasSuffix("."), let num = Int(prefix.dropLast()), num >= 0 {
                    return .listStyle(.numbered, checked: false, number: num)
                }
                return nil
            }
        }

        private func applyInlineMarkdownIfMatched(text: String, existingRuns: [TextRunAttributes], caretOffset: Int) -> (String, [TextRunAttributes], Int)? {
            let ns = text as NSString
            guard caretOffset > 2, caretOffset <= ns.length else { return nil }
            let upToCaret = ns.substring(to: caretOffset)

            let rules: [(pattern: String, apply: (inout TextRunAttributes, NSTextCheckingResult, NSString) -> String)] = [
                (#"\*\*([^\s*](?:[^*]*[^\s*])?)\*\*$"#, { run, m, s in
                    run.isBold = true
                    return s.substring(with: m.range(at: 1))
                }),
                (#"(?<!\*)\*([^\s*](?:[^*]*[^\s*])?)\*$"#, { run, m, s in
                    run.isItalic = true
                    return s.substring(with: m.range(at: 1))
                }),
                (#"`([^`]+)`$"#, { run, m, s in
                    run.isCode = true
                    return s.substring(with: m.range(at: 1))
                }),
                (#"~~([^\s~](?:[^~]*[^\s~])?)~~$"#, { run, m, s in
                    run.isStrikethrough = true
                    return s.substring(with: m.range(at: 1))
                }),
                (#"(?:==|::)([^\s=:](?:[^=:]*[^\s=:])?)(?:==|::)$"#, { run, m, s in
                    run.highlightColor = "#DFC370"
                    return s.substring(with: m.range(at: 1))
                }),
                (#"\[([^\[\]]+)\]\(([^)\s]+)\)$"#, { run, m, s in
                    run.linkURL = s.substring(with: m.range(at: 2))
                    return s.substring(with: m.range(at: 1))
                })
            ]

            let upToCaretNS = upToCaret as NSString
            for rule in rules {
                guard let regex = try? NSRegularExpression(pattern: rule.pattern),
                      let match = regex.firstMatch(in: upToCaret, range: NSRange(location: 0, length: upToCaretNS.length)) else {
                    continue
                }
                var newRun = TextRunAttributes(location: match.range.location, length: 0)
                let inner = rule.apply(&newRun, match, upToCaretNS)
                newRun.length = (inner as NSString).length

                let replaced = ns.replacingCharacters(in: match.range, with: inner)
                var runs = adjustRunsForEdit(existingRuns, range: match.range, replacementUTF16Len: newRun.length)
                runs.append(newRun)
                let normalized = TextRunAttributes.normalize(runs, utf16Length: (replaced as NSString).length)
                let newCaret = match.range.location + newRun.length
                return (replaced, normalized, newCaret)
            }
            return nil
        }

        private func adjustRunsForEdit(_ runs: [TextRunAttributes], range: NSRange, replacementUTF16Len: Int) -> [TextRunAttributes] {
            let delta = replacementUTF16Len - range.length
            return runs.compactMap { run in
                var copy = run
                if copy.upperBound <= range.location {
                    return copy
                } else if copy.location >= range.location + range.length {
                    copy.location += delta
                    return copy
                } else {
                    // Overlap: clamp before edit start
                    let newLen = max(0, range.location - copy.location)
                    if newLen == 0 { return nil }
                    copy.length = newLen
                    return copy
                }
            }
        }
    }
}

/// Custom NSTextView subclass intercepting Return/Shift+Return/Cmd+Return, Backspace-at-0,
/// Forward-Delete-at-end, Tab/Shift+Tab, vertical boundary arrow jumps, Cmd+A escalation,
/// Esc escalation, and inline formatting shortcuts.
final class RoweNSTextView: NSTextView {
    weak var coordinator: RoweBlockTextView.Coordinator?

    override var intrinsicContentSize: NSSize {
        guard let lm = layoutManager, let tc = textContainer else {
            return super.intrinsicContentSize
        }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let minLineHeight = (font?.ascender ?? 15) - (font?.descender ?? -4) + (font?.leading ?? 2) + 6
        let height = max(minLineHeight, ceil(used.height + textContainerInset.height * 2 + 2))
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.size.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged {
            invalidateIntrinsicContentSize()
        }
    }

    func caretRectInWindow() -> CGRect? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        lm.ensureLayout(for: tc)
        let sel = selectedRange()
        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: min(sel.location, (string as NSString).length), length: 0), actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        if rect.height < 12 { rect.size.height = 18 }
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return convert(rect, to: nil)
    }

    private func caretXCoordinate() -> CGFloat {
        guard let lm = layoutManager, let tc = textContainer else { return 0 }
        lm.ensureLayout(for: tc)
        let sel = selectedRange()
        let len = (string as NSString).length
        guard len > 0 else { return 0 }
        let idx = min(sel.location, len)
        if idx == len {
            let extra = lm.extraLineFragmentRect
            if extra.height > 0 { return extra.minX }
            let g = lm.glyphIndexForCharacter(at: max(0, len - 1))
            let r = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc)
            return r.maxX
        }
        let g = lm.glyphIndexForCharacter(at: idx)
        let r = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc)
        return r.minX
    }

    private func isOnFirstVisualLine() -> Bool {
        guard let lm = layoutManager, let tc = textContainer else { return true }
        lm.ensureLayout(for: tc)
        let len = (string as NSString).length
        guard len > 0 else { return true }
        let sel = selectedRange()
        let firstLineRect = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        if sel.location >= len {
            let extra = lm.extraLineFragmentRect
            if extra.height > 0 { return abs(extra.minY - firstLineRect.minY) < 1 }
            let lastGlyph = lm.glyphIndexForCharacter(at: len - 1)
            let curRect = lm.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            return abs(curRect.minY - firstLineRect.minY) < 1
        }
        let g = lm.glyphIndexForCharacter(at: sel.location)
        let curRect = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
        return abs(curRect.minY - firstLineRect.minY) < 1
    }

    private func isOnLastVisualLine() -> Bool {
        guard let lm = layoutManager, let tc = textContainer else { return true }
        lm.ensureLayout(for: tc)
        let len = (string as NSString).length
        guard len > 0 else { return true }
        let sel = selectedRange()
        let extra = lm.extraLineFragmentRect
        let lastLineMinY: CGFloat = extra.height > 0
            ? extra.minY
            : lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: len - 1), effectiveRange: nil).minY
        if sel.location >= len { return true }
        let g = lm.glyphIndexForCharacter(at: sel.location)
        let curRect = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
        return abs(curRect.minY - lastLineMinY) < 1
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])

        // Inline formatting shortcuts
        if mods == .command, let chars = event.charactersIgnoringModifiers?.lowercased() {
            switch chars {
            case "b":
                coordinator?.toggleInlineStyle(.bold, in: self)
                return
            case "i":
                coordinator?.toggleInlineStyle(.italic, in: self)
                return
            case "e":
                coordinator?.toggleInlineStyle(.code, in: self)
                return
            case "a":
                let len = (string as NSString).length
                let sel = selectedRange()
                if len == 0 || sel.length == len {
                    window?.makeFirstResponder(nil)
                    coordinator?.parent.onEscalateSelectAll()
                } else {
                    setSelectedRange(NSRange(location: 0, length: len))
                }
                return
            default:
                break
            }
        }

        if mods == [.command, .shift], let chars = event.charactersIgnoringModifiers?.lowercased() {
            switch chars {
            case "x":
                coordinator?.toggleInlineStyle(.strikethrough, in: self)
                return
            case "h":
                coordinator?.toggleInlineStyle(.highlight, in: self)
                return
            default:
                break
            }
        }

        // Cmd+Return toggles todo/toggle state
        if mods == .command && (event.keyCode == 36 || event.keyCode == 76) {
            coordinator?.parent.onCmdReturn()
            return
        }

        // Shift+Return inserts soft newline inside the same block
        if mods == .shift && (event.keyCode == 36 || event.keyCode == 76) {
            insertNewlineIgnoringFieldEditor(nil)
            return
        }

        // Plain Return splits the block at caret offset
        if mods.isEmpty && (event.keyCode == 36 || event.keyCode == 76) {
            if hasMarkedText() {
                super.keyDown(with: event)
                return
            }
            coordinator?.parent.onReturnSplit(selectedRange().location)
            return
        }

        // Tab / Shift+Tab indents or outdents block
        if event.keyCode == 48 {
            if mods == .shift {
                coordinator?.parent.onIndent(-1)
                return
            } else if mods.isEmpty {
                coordinator?.parent.onIndent(1)
                return
            }
        }

        // Esc escalates inlineSelection -> blockSelection
        if event.keyCode == 53 && mods.isEmpty {
            window?.makeFirstResponder(nil)
            coordinator?.parent.onEscapeToBlockSelection()
            return
        }

        // Backspace at offset 0 (no selection)
        if event.keyCode == 51 && mods.isEmpty {
            let sel = selectedRange()
            if sel.location == 0 && sel.length == 0 {
                coordinator?.parent.onBackspaceAtStart()
                return
            }
        }

        // Forward Delete at end of block
        if event.keyCode == 117 && mods.isEmpty {
            let sel = selectedRange()
            if sel.location == (string as NSString).length && sel.length == 0 {
                coordinator?.parent.onForwardDeleteAtEnd()
                return
            }
        }

        // Arrow Up (126) & Arrow Down (125) boundary crossing with sticky desiredCaretX
        if event.keyCode == 126 && (mods.isEmpty || mods == .shift) {
            let x = coordinator?.stickyDesiredX ?? caretXCoordinate()
            coordinator?.stickyDesiredX = x
            if isOnFirstVisualLine() {
                coordinator?.parent.onMoveVertical(-1, Double(x), mods == .shift)
                return
            }
        }

        if event.keyCode == 125 && (mods.isEmpty || mods == .shift) {
            let x = coordinator?.stickyDesiredX ?? caretXCoordinate()
            coordinator?.stickyDesiredX = x
            if isOnLastVisualLine() {
                coordinator?.parent.onMoveVertical(1, Double(x), mods == .shift)
                return
            }
        }

        // Horizontal arrows reset sticky X
        if event.keyCode == 123 || event.keyCode == 124 {
            coordinator?.stickyDesiredX = nil
        }

        super.keyDown(with: event)
    }
}
