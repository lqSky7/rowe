import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RoweCore

/// Native AppKit multi-line text input for TaskEditorPopover supporting:
/// - Enter = submit / create task
/// - Shift + Enter = insert newline
/// - Cmd + V with image on pasteboard = attach image as `#image N` chip
/// - Full native macOS Undo/Redo (`allowsUndo = true`)
private struct TaskEditorTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onPasteImage: (NSImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> TaskInputNSTextView {
        let tv = TaskInputNSTextView()
        tv.delegate = context.coordinator
        tv.coordinator = context.coordinator
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        tv.textColor = NSColor.labelColor
        tv.insertionPointColor = NSColor.labelColor
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.textContainer?.lineFragmentPadding = 2
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.string = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        }
        return tv
    }

    func updateNSView(_ tv: TaskInputNSTextView, context: Context) {
        context.coordinator.parent = self
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            let len = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
            tv.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TaskInputNSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 520
        if abs(nsView.frame.width - width) > 0.5 {
            nsView.frame.size.width = width
        }
        let h = nsView.intrinsicContentSize.height
        return CGSize(width: width, height: h)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TaskEditorTextView
        init(parent: TaskEditorTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? TaskInputNSTextView else { return }
            parent.text = tv.string
            tv.invalidateIntrinsicContentSize()
        }
    }
}

private final class TaskInputNSTextView: NSTextView {
    weak var coordinator: TaskEditorTextView.Coordinator?

    override var intrinsicContentSize: NSSize {
        guard let lm = layoutManager, let tc = textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 26)
        }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let h = min(140, max(26, ceil(used.height + textContainerInset.height * 2 + 4)))
        return NSSize(width: NSView.noIntrinsicMetric, height: h)
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.keyCode == 36 || event.keyCode == 76 {
            if mods == .shift {
                insertNewlineIgnoringFieldEditor(nil)
                invalidateIntrinsicContentSize()
                return
            } else if mods.isEmpty || mods == .command {
                coordinator?.parent.onSubmit()
                return
            }
        }
        super.keyDown(with: event)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [.png, .tiff, .fileURL]
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)) {
            if pasteboardContainsImage(NSPasteboard.general) {
                return true
            }
        }
        return super.validateUserInterfaceItem(item)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if window?.firstResponder === self,
           mods == .command,
           event.charactersIgnoringModifiers?.lowercased() == "v",
           pasteboardContainsImage(NSPasteboard.general) {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func paste(_ sender: Any?) {
        if let img = extractImageFromPasteboard(NSPasteboard.general) {
            coordinator?.parent.onPasteImage(img)
            return
        }
        super.paste(sender)
    }

    private func pasteboardContainsImage(_ pb: NSPasteboard) -> Bool {
        if pb.data(forType: .png) != nil || pb.data(forType: .tiff) != nil {
            return true
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL],
           !urls.isEmpty {
            return true
        }
        return pb.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    private func extractImageFromPasteboard(_ pb: NSPasteboard) -> NSImage? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL],
           let firstURL = urls.first,
           let img = NSImage(contentsOf: firstURL) {
            return img
        }
        if let pngData = pb.data(forType: .png), let img = NSImage(data: pngData) {
            return img
        }
        if let tiffData = pb.data(forType: .tiff), let img = NSImage(data: tiffData) {
            return img
        }
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img = images.first {
            return img
        }
        return nil
    }
}

struct TaskEditorPopover: View {
    @Bindable var store: WorkspaceStore
    let request: TaskEditorRequest
    var onCommitTaskForFlight: ((ResolvedTaskItem, CGRect, CGRect) -> Void)? = nil
    var onClose: () -> Void

    @State private var text: String
    @State private var taskState: TaskCompletionState
    @State private var scheduleDate: Date?
    @State private var deadlineDate: Date?
    @State private var reminderDate: Date?
    @State private var repeatRule: RepeatRule?
    @State private var attachedImages: [String]
    @State private var showSchedulePicker = false
    @State private var showDeadlinePicker = false
    @State private var popoverFrame: CGRect = .zero
    @State private var textFieldFrame: CGRect = .zero

    private var existingItem: ResolvedTaskItem? {
        if case .edit(let item) = request { return item }
        return nil
    }

    init(
        store: WorkspaceStore,
        request: TaskEditorRequest,
        onCommitTaskForFlight: ((ResolvedTaskItem, CGRect, CGRect) -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.request = request
        self.onCommitTaskForFlight = onCommitTaskForFlight
        self.onClose = onClose
        switch request {
        case .create(let defaultDate):
            _text = State(initialValue: "")
            _taskState = State(initialValue: .pending)
            _scheduleDate = State(initialValue: defaultDate)
            _deadlineDate = State(initialValue: nil)
            _reminderDate = State(initialValue: nil)
            _repeatRule = State(initialValue: nil)
            _attachedImages = State(initialValue: [])
        case .edit(let item):
            _text = State(initialValue: item.block.content)
            _taskState = State(initialValue: item.block.task?.state ?? .pending)
            _scheduleDate = State(initialValue: item.block.task?.scheduleDate)
            _deadlineDate = State(initialValue: item.block.task?.deadlineDate)
            _reminderDate = State(initialValue: item.block.task?.reminderDate)
            _repeatRule = State(initialValue: item.block.task?.repeatRule)
            _attachedImages = State(initialValue: item.block.task?.attachedImagesBase64 ?? [])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    Text(existingItem.map { $0.isInbox ? "Inbox" : $0.documentTitle } ?? "Inbox")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GlassCircleButton(systemImage: "xmark", helpText: "Close (Esc)", size: 24, iconSize: 10) {
                    commitAndClose()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            HStack(alignment: .top, spacing: 12) {
                TaskCheckboxControl(state: taskState) { newState in
                    taskState = newState
                    if existingItem != nil { persistExistingChanges() }
                }
                .padding(.top, 3)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("What needs to be done?")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                            .padding(.leading, 3)
                            .allowsHitTesting(false)
                    }
                    TaskEditorTextView(
                        text: $text,
                        placeholder: "What needs to be done?",
                        onSubmit: {
                            HapticsManager.shared.tap()
                            commitAndClose()
                        },
                        onPasteImage: { image in
                            attachImage(image)
                        }
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named("macWindowSpace"))
                } action: { frame in
                    textFieldFrame = frame
                }
                .onChange(of: text) { _, _ in
                    if existingItem != nil { persistExistingChanges() }
                }
            }
            .padding(.vertical, 2)

            // Attached image chips (#image 1, #image 2) with hover preview
            if !attachedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(attachedImages.enumerated()), id: \.offset) { idx, b64 in
                            TaskImageChip(index: idx + 1, base64: b64) {
                                withAnimation(CraftTheme.microSpring(reduceMotion: store.settings.reduceAnimations)) {
                                    attachedImages.remove(at: idx)
                                    if existingItem != nil { persistExistingChanges() }
                                }
                            }
                            .transition(.roweUnblur)
                        }
                    }
                    .padding(.leading, 32)
                }
            }

            HStack(spacing: 12) {
                Button {
                    HapticsManager.shared.tap()
                    showSchedulePicker.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: repeatRule != nil ? "repeat" : "calendar")
                            .font(.system(size: 12))
                        Text(scheduleLabel)
                            .font(.system(size: 13, weight: .medium))
                        if repeatRule != nil {
                            Text("Repeating")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSchedulePicker, arrowEdge: .bottom) {
                    TaskDateRepeatPicker(
                        selectedDate: $scheduleDate,
                        repeatRule: $repeatRule,
                        reminderDate: $reminderDate
                    ) {
                        showSchedulePicker = false
                    }
                    .onChange(of: scheduleDate) { _, _ in if existingItem != nil { persistExistingChanges() } }
                    .onChange(of: repeatRule) { _, _ in if existingItem != nil { persistExistingChanges() } }
                    .onChange(of: reminderDate) { _, _ in if existingItem != nil { persistExistingChanges() } }
                }

                Button {
                    HapticsManager.shared.tap()
                    showDeadlinePicker.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "flag")
                            .font(.system(size: 12))
                        Text(deadlineDate.map(shortDateLabel) ?? "Deadline")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(deadlineDate == nil ? .secondary : .primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDeadlinePicker, arrowEdge: .bottom) {
                    TaskDateRepeatPicker(
                        selectedDate: $deadlineDate,
                        repeatRule: .constant(nil),
                        reminderDate: .constant(nil)
                    ) {
                        showDeadlinePicker = false
                    }
                    .onChange(of: deadlineDate) { _, _ in if existingItem != nil { persistExistingChanges() } }
                }

                Button {
                    HapticsManager.shared.tap()
                    pickImageFromDisk()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 12.5))
                        Text("Image")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Attach Image (or paste ⌘V)")

                Spacer()

                if let item = existingItem {
                    GlassPillButton("Open Doc", systemImage: "arrow.up.right") {
                        commitAndClose()
                        store.navigate(to: .document(item.documentId))
                    }
                } else {
                    Button {
                        HapticsManager.shared.tap()
                        commitAndClose()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Add Task")
                                .font(.system(size: 13, weight: .semibold))
                            Text("↵")
                                .font(.system(size: 11, weight: .bold))
                                .opacity(0.8)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.accentColor))
                    }
                    .buttonStyle(RowePressScaleButtonStyle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoweNativeGlassBackdrop(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("macWindowSpace"))
        } action: { frame in
            popoverFrame = frame
        }
    }

    private func attachImage(_ image: NSImage) {
        guard let b64 = TaskImageEncoder.encodeToBase64(image) else { return }
        HapticsManager.shared.tap()
        withAnimation(CraftTheme.microSpring(reduceMotion: store.settings.reduceAnimations)) {
            attachedImages.append(b64)
            if existingItem != nil { persistExistingChanges() }
        }
    }

    private func pickImageFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let img = NSImage(contentsOf: url) {
                attachImage(img)
            }
        }
    }

    private var scheduleLabel: String {
        guard let date = scheduleDate else { return "Schedule" }
        return shortDateLabel(date)
    }

    private func shortDateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    private func persistExistingChanges() {
        guard let item = existingItem else { return }
        store.updateBlock(in: item.documentId, blockId: item.block.id, coalesceUndo: true) { block in
            block.content = text
            block.listStyle = .todo
            var meta = block.task ?? TaskMetadata(isInbox: item.isInbox)
            meta.scheduleDate = scheduleDate
            meta.deadlineDate = deadlineDate
            meta.reminderDate = reminderDate
            meta.repeatRule = repeatRule
            meta.attachedImagesBase64 = attachedImages
            meta.applyStateTransition(to: taskState)
            block.task = meta
        }
    }

    private func commitAndClose() {
        if existingItem != nil {
            persistExistingChanges()
            store.flushPendingSyncImmediately()
            onClose()
            return
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty || !attachedImages.isEmpty {
                let created = store.addInboxTask(
                    title: trimmed.isEmpty ? "Image Task" : trimmed,
                    scheduleDate: scheduleDate,
                    deadlineDate: deadlineDate,
                    repeatRule: repeatRule,
                    attachedImagesBase64: attachedImages
                )
                if reminderDate != nil || taskState != .pending {
                    store.updateBlock(in: created.documentId, blockId: created.block.id) { blk in
                        blk.task?.reminderDate = reminderDate
                        blk.task?.applyStateTransition(to: taskState)
                    }
                }
                if !store.settings.reduceAnimations && store.settings.crazyTaskComposeAnimation, let onCommitTaskForFlight {
                    onCommitTaskForFlight(created, textFieldFrame, popoverFrame)
                    return
                }
            }
        }
        onClose()
    }
}
