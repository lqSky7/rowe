import PhotosUI
import SwiftUI
import UIKit
import RoweCore

/// Full-featured iOS task editor matching macOS `TaskEditorPopover` + `TaskDateRepeatPicker`:
/// Title, Notes, Schedule Date (graphical calendar + Clear Date), Reminder time, Repeat frequency,
/// Deadline Date (graphical calendar + Clear Date), and multi-image photo attachments.
struct IOSTaskEditorSheet: View {
    @Bindable var store: WorkspaceStore
    let item: ResolvedTaskItem
    var onClose: () -> Void

    @State private var text: String
    @State private var notes: String
    @State private var taskState: TaskCompletionState
    @State private var scheduleDate: Date?
    @State private var deadlineDate: Date?
    @State private var reminderDate: Date?
    @State private var repeatRule: RepeatRule?
    @State private var attachedImages: [String]
    @State private var expandedPicker: ActivePicker? = nil
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var previewImageBase64: String? = nil

    private enum ActivePicker {
        case schedule
        case deadline
    }

    private var selectedAccent: Color {
        Color(hex: store.settings.accentColor.hex)
    }

    init(store: WorkspaceStore, item: ResolvedTaskItem, onClose: @escaping () -> Void) {
        self.store = store
        self.item = item
        self.onClose = onClose
        _text = State(initialValue: item.block.content)
        _notes = State(initialValue: item.block.task?.notes ?? "")
        _taskState = State(initialValue: item.block.task?.state ?? .pending)
        _scheduleDate = State(initialValue: item.block.task?.scheduleDate)
        _deadlineDate = State(initialValue: item.block.task?.deadlineDate)
        _reminderDate = State(initialValue: item.block.task?.reminderDate)
        _repeatRule = State(initialValue: item.block.task?.repeatRule)
        _attachedImages = State(initialValue: item.block.task?.attachedImagesBase64 ?? [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text(item.isInbox ? "Inbox" : item.documentTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        IOSHaptics.shared.tap()
                        persistAndClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.10)))
                    }
                    .buttonStyle(RowePressScaleStyle())
                }

                // Task checkbox + Title
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        IOSHaptics.shared.tap()
                        taskState = (taskState == .pending) ? .completed : .pending
                        persistChanges()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(taskState == .canceled ? Color.red : (taskState == .completed ? selectedAccent : Color.clear))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(
                                            taskState == .canceled ? Color.red : (taskState == .completed ? Color.clear : Color.primary.opacity(0.35)),
                                            lineWidth: 1.5
                                        )
                                )
                            if taskState == .completed {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            } else if taskState == .canceled {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 3)

                    TextField("What needs to be done?", text: $text, axis: .vertical)
                        .font(.system(size: 18, weight: .medium))
                        .lineLimit(1...5)
                        .onChange(of: text) { _, _ in persistChanges() }
                }

                // Notes
                TextField("Add notes…", text: $notes, axis: .vertical)
                    .font(.system(size: 14.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1...5)
                    .padding(.leading, 34)
                    .onChange(of: notes) { _, _ in persistChanges() }

                // Attached images strip
                if !attachedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(attachedImages.enumerated()), id: \.offset) { idx, b64 in
                                if let data = Data(base64Encoded: b64), let uiImg = UIImage(data: data) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: uiImg)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 76, height: 76)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .onTapGesture { previewImageBase64 = b64 }

                                        Button {
                                            IOSHaptics.shared.tap()
                                            withAnimation(IOSTheme.microSpring(reduceMotion: store.settings.reduceAnimations)) {
                                                attachedImages.remove(at: idx)
                                                persistChanges()
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundStyle(.white, .black.opacity(0.65))
                                        }
                                        .offset(x: 4, y: -4)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Action pills row matching macOS (Schedule Date, Deadline, Image)
                HStack(spacing: 10) {
                    Button {
                        IOSHaptics.shared.tap()
                        withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            expandedPicker = (expandedPicker == .schedule) ? nil : .schedule
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: repeatRule != nil ? "repeat" : "calendar")
                                .font(.system(size: 13))
                            Text(scheduleDate.map(shortDateLabel) ?? "Schedule")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(expandedPicker == .schedule || scheduleDate != nil ? .primary : .secondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .roweIOSGlassCapsule(interactive: true)
                    }
                    .buttonStyle(RowePressScaleStyle())

                    Button {
                        IOSHaptics.shared.tap()
                        withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            expandedPicker = (expandedPicker == .deadline) ? nil : .deadline
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "flag")
                                .font(.system(size: 13))
                                .foregroundStyle(deadlineDate != nil ? .orange : .secondary)
                            Text(deadlineDate.map(shortDateLabel) ?? "Deadline")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(expandedPicker == .deadline || deadlineDate != nil ? .primary : .secondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .roweIOSGlassCapsule(interactive: true)
                    }
                    .buttonStyle(RowePressScaleStyle())

                    PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 5, matching: .images) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                    }
                    .roweIOSGlass(in: Circle(), interactive: true)

                    Spacer()
                }

                // Inline Calendar + Reminder + Repeat panel (matches macOS TaskDateRepeatPicker)
                if expandedPicker == .schedule {
                    schedulePickerPanel
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                } else if expandedPicker == .deadline {
                    deadlinePickerPanel
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }

                Divider().opacity(0.25)

                // Footer actions
                HStack {
                    Button(role: .destructive) {
                        IOSHaptics.shared.errorBuzz()
                        store.deleteBlock(in: item.documentId, blockId: item.block.id)
                        onClose()
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        IOSHaptics.shared.tap()
                        persistAndClose()
                    } label: {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(selectedAccent))
                    }
                    .buttonStyle(RowePressScaleStyle())
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: photoPickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                for pickerItem in newItems {
                    if let data = try? await pickerItem.loadTransferable(type: Data.self),
                       let uiImg = UIImage(data: data),
                       let compressed = uiImg.jpegData(compressionQuality: 0.72) {
                        await MainActor.run {
                            attachedImages.append(compressed.base64EncodedString())
                            persistChanges()
                        }
                    }
                }
                await MainActor.run { photoPickerItems.removeAll() }
            }
        }
        .sheet(isPresented: Binding(
            get: { previewImageBase64 != nil },
            set: { if !$0 { previewImageBase64 = nil } }
        )) {
            if let b64 = previewImageBase64, let data = Data(base64Encoded: b64), let uiImg = UIImage(data: data) {
                NavigationStack {
                    Image(uiImage: uiImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { previewImageBase64 = nil }
                            }
                        }
                }
            }
        }
    }

    private var schedulePickerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker(
                "Schedule Date",
                selection: Binding(
                    get: { scheduleDate ?? Calendar.current.startOfDay(for: Date()) },
                    set: {
                        scheduleDate = Calendar.current.startOfDay(for: $0)
                        persistChanges()
                    }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .tint(selectedAccent)

            Button {
                IOSHaptics.shared.tap()
                scheduleDate = nil
                repeatRule = nil
                persistChanges()
            } label: {
                Text("Clear Date")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)

            Divider().opacity(0.25)

            // Remind Me
            HStack {
                Image(systemName: "alarm")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                if let rem = reminderDate {
                    DatePicker(
                        "Remind Me",
                        selection: Binding(
                            get: { rem },
                            set: {
                                reminderDate = $0
                                persistChanges()
                            }
                        ),
                        displayedComponents: [.hourAndMinute]
                    )
                    .labelsHidden()
                    Spacer()
                    Button {
                        reminderDate = nil
                        persistChanges()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Remind Me…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        IOSHaptics.shared.tap()
                        let base = scheduleDate ?? Date()
                        reminderDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base
                        persistChanges()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Repeat Rule
            HStack {
                Image(systemName: "repeat")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("Repeat")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("None") {
                        repeatRule = nil
                        persistChanges()
                    }
                    ForEach(RepeatFrequency.allCases, id: \.self) { freq in
                        Button(freq.rawValue) {
                            let start = scheduleDate ?? Calendar.current.startOfDay(for: Date())
                            let weekday = Calendar.current.component(.weekday, from: start)
                            repeatRule = RepeatRule(
                                frequency: freq,
                                weekdayIndex: freq == .weekly ? weekday : nil,
                                startDate: start
                            )
                            if scheduleDate == nil { scheduleDate = start }
                            persistChanges()
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(repeatRule?.displayLabel ?? "None")
                            .font(.system(size: 13.5, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(0.10)))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private var deadlinePickerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker(
                "Deadline Date",
                selection: Binding(
                    get: { deadlineDate ?? Calendar.current.startOfDay(for: Date()) },
                    set: {
                        deadlineDate = Calendar.current.startOfDay(for: $0)
                        persistChanges()
                    }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .tint(selectedAccent)

            Button {
                IOSHaptics.shared.tap()
                deadlineDate = nil
                persistChanges()
            } label: {
                Text("Clear Deadline")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func shortDateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    private func persistChanges() {
        store.updateBlock(in: item.documentId, blockId: item.block.id, coalesceUndo: true) { block in
            block.content = text
            block.listStyle = .todo
            var meta = block.task ?? TaskMetadata(isInbox: item.isInbox)
            meta.notes = notes
            meta.scheduleDate = scheduleDate
            meta.deadlineDate = deadlineDate
            meta.reminderDate = reminderDate
            meta.repeatRule = repeatRule
            meta.attachedImagesBase64 = attachedImages
            meta.applyStateTransition(to: taskState)
            block.task = meta
        }
    }

    private func persistAndClose() {
        persistChanges()
        onClose()
    }
}
