import SwiftUI
import RoweCore

enum IOSTaskViewMode {
    case calendar
    case allTasks
}

/// iOS Calendar & Tasks view matching IMG_5040 + IMG_5055:
/// - Date-grouped timeline (`Nov 26 / Today · Thursday` in accent color, Tomorrow, Upcoming)
/// - Single-tap complete with sweeping strikethrough & haptics, double-tap red cross-out without jump
/// - NumericText transitions for live remaining counts.
struct IOSCalendarTasksView: View {
    @Bindable var store: WorkspaceStore
    let mode: IOSTaskViewMode
    var onOpenSettings: () -> Void
    var onOpenQuickAdd: () -> Void

    @State private var showCompleted: Bool = false

    private var allTasks: [ResolvedTaskItem] {
        store.allTasks()
    }

    private var upcomingDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Top bar matching IMG_5040
                HStack {
                    Button {
                        IOSHaptics.shared.tap()
                        onOpenSettings()
                    } label: {
                        IOSSpaceAvatar(space: store.space, size: 38, cornerRadius: 11)
                    }
                    .buttonStyle(RowePressScaleStyle())

                    Spacer()

                    HStack(spacing: 14) {
                        Menu {
                            Toggle("Show Completed", isOn: $showCompleted)
                            Button("Add Task", systemImage: "plus") { onOpenQuickAdd() }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 30, height: 30)
                        }

                        Button {
                            IOSHaptics.shared.tap()
                            if store.isSignedIn {
                                Task { await store.syncWithBackend() }
                            } else {
                                store.isLoginSheetPresented = true
                            }
                        } label: {
                            Image(systemName: "bell")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(RowePressScaleStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .roweIOSGlassCapsule(interactive: true)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                if mode == .calendar {
                    ForEach(upcomingDays, id: \.self) { day in
                        daySection(for: day)
                    }
                } else {
                    allTasksBody
                }
            }
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func daySection(for day: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)
        let isTomorrow = cal.isDateInTomorrow(day)
        let dayTasks = allTasks.filter { item in
            let state = item.block.task?.state ?? .pending
            if !showCompleted && state != .pending { return false }
            if let sched = item.block.task?.scheduleDate {
                return cal.isDate(sched, inSameDayAs: day)
            }
            return isToday
        }

        let monthDay = day.formatted(.dateTime.month(.abbreviated).day())
        let weekday = day.formatted(.dateTime.weekday(.wide))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    if isToday {
                        Text(monthDay)
                            .font(.system(size: 28, weight: .bold))
                        HStack(spacing: 6) {
                            Text("Today")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            Text("· \(weekday)")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text(monthDay)
                                .font(.system(size: 19, weight: .bold))
                            if isTomorrow {
                                Text("Tomorrow")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text("· \(weekday)")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button {
                    IOSHaptics.shared.tap()
                    onOpenQuickAdd()
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
            }
            .padding(.horizontal, 18)

            if dayTasks.isEmpty && isToday {
                Text("All clear for today")
                    .font(.system(size: 14.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 2) {
                    ForEach(dayTasks) { item in
                        IOSTaskRow(store: store, item: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var allTasksBody: some View {
        let pending = allTasks.filter { ($0.block.task?.state ?? .pending) == .pending }
        let completed = allTasks.filter { ($0.block.task?.state ?? .pending) != .pending }

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tasks")
                    .font(.system(size: 32, weight: .bold))
                Spacer()
                Text("\(pending.count) remaining")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 18)

            if pending.isEmpty {
                ContentUnavailableView(
                    "All Tasks Done",
                    systemImage: "checkmark.circle.fill",
                    description: Text("Tap + below to capture a new task.")
                )
                .padding(.top, 40)
            } else {
                ForEach(pending) { item in
                    IOSTaskRow(store: store, item: item)
                }
            }

            if !completed.isEmpty {
                DisclosureGroup("Completed (\(completed.count))", isExpanded: $showCompleted) {
                    ForEach(completed) { item in
                        IOSTaskRow(store: store, item: item)
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
        }
    }
}

struct IOSTaskRow: View {
    @Bindable var store: WorkspaceStore
    let item: ResolvedTaskItem
    @State private var redFlash = false

    private var state: TaskCompletionState {
        item.block.task?.state ?? .pending
    }

    var body: some View {
        HStack(spacing: 12) {
            // Single tap = complete, Double tap = red cross-out (zero layout jump)
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        redFlash || state == .cancelled
                            ? Color.red
                            : (state == .completed ? Color.primary.opacity(0.65) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                redFlash || state == .cancelled
                                    ? Color.red
                                    : (state == .completed ? Color.clear : Color.primary.opacity(0.35)),
                                lineWidth: 1.5
                            )
                    )
                if state == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                } else if state == .cancelled || redFlash {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 21, height: 21)
            .contentShape(Rectangle().inset(by: -8))
            .onTapGesture(count: 2) {
                IOSHaptics.shared.errorBuzz()
                withAnimation(.easeInOut(duration: 0.16)) { redFlash = true }
                store.setTaskState(docId: item.documentId, blockId: item.block.id, state: state == .cancelled ? .pending : .cancelled)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { redFlash = false }
            }
            .onTapGesture(count: 1) {
                let next: TaskCompletionState = state == .pending ? .completed : .pending
                if next == .completed { IOSHaptics.shared.taskComplete() } else { IOSHaptics.shared.tap() }
                withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                    store.setTaskState(docId: item.documentId, blockId: item.block.id, state: next)
                }
            }

            Text(item.block.content.isEmpty ? "Untitled Task" : item.block.content)
                .font(.system(size: 16))
                .strikethrough(state != .pending, color: state == .cancelled ? .red.opacity(0.8) : .secondary)
                .foregroundStyle(state != .pending ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 6)

            if item.isInbox {
                Text("Inbox")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
            }

            if item.block.task?.repeatRule != nil {
                Image(systemName: "repeat")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

/// Floating Quick Add Card above the keyboard matching IMG_5055.
struct IOSQuickAddTaskCard: View {
    @Bindable var store: WorkspaceStore
    var onClose: () -> Void

    @State private var text: String = ""
    @State private var scheduleDate: Date = Calendar.current.startOfDay(for: Date())
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Menu {
                    Button("Today") { scheduleDate = Calendar.current.startOfDay(for: Date()) }
                    Button("Tomorrow") {
                        scheduleDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                    }
                    Button("Next Week") {
                        scheduleDate = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14))
                        Text(Calendar.current.isDateInToday(scheduleDate) ? "Today" : scheduleDate.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: 15, weight: .medium))
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    IOSHaptics.shared.tap()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.10)))
                }
            }

            TextField("Add to Daily Note or Task", text: $text, axis: .vertical)
                .focused($isFocused)
                .font(.system(size: 17))
                .lineLimit(1...4)
                .submitLabel(.done)
                .onSubmit { saveAndClose() }

            HStack(spacing: 14) {
                Image(systemName: "doc.plaintext")
                    .foregroundStyle(.secondary)
                Image(systemName: "checkmark.square")
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Button {
                    saveAndClose()
                } label: {
                    Text("Add")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(RowePressScaleStyle())
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .roweIOSGlassRoundedRect(radius: 24, interactive: true)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true }
        }
    }

    private func saveAndClose() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        IOSHaptics.shared.taskComplete()
        _ = store.addInboxTask(title: trimmed, scheduleDate: scheduleDate)
        onClose()
    }
}
