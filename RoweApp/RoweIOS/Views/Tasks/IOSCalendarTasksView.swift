import SwiftUI
import RoweCore

enum IOSTaskViewMode {
    case calendar
    case allTasks
}

/// iOS Calendar & Tasks view refined to match Craft's calm rhythm:
/// - Date-grouped timeline with crisp hairline separators under every day header
/// - Bolder, easy-to-read multiline task titles
/// - "Show Previous Days" revealed on a gentle pull-down (below search trigger) and hidden when leaving the tab
/// - "View Completed" shown only once all tasks for a day are completed (replacing the sparkle banner)
/// - Tapping any task or '+' opens the unified floating Task Composer (Date, Deadline, Repeat, Reminder, Notes).
struct IOSCalendarTasksView: View {
    @Bindable var store: WorkspaceStore
    let mode: IOSTaskViewMode
    let zoomNamespace: Namespace.ID
    var onOpenSettings: () -> Void
    var onOpenQuickAdd: (Date?) -> Void
    var onEditTask: (ResolvedTaskItem) -> Void

    @State private var showCompleted: Bool = false
    @State private var showPreviousDays: Bool = false
    @State private var isPreviousDaysRevealed: Bool = false
    @State private var expandedCompletedDays: Set<Date> = []
    @State private var lingeringTaskIds: Set<String> = []
    @State private var lingerTimers: [String: Task<Void, Never>] = [:]

    private var reduceMotion: Bool {
        store.settings.reduceAnimations
    }

    private var selectedAccent: Color {
        Color(hex: store.settings.accentColor.hex)
    }

    private var allTasks: [ResolvedTaskItem] {
        store.allTasks()
    }

    private var visibleDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startOffset = showPreviousDays ? -5 : 0
        return (startOffset...6).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Top bar
                HStack {
                    Button {
                        IOSHaptics.shared.tap()
                        onOpenSettings()
                    } label: {
                        IOSSpaceAvatar(
                            space: store.space,
                            size: 38,
                            cornerRadius: 11,
                            syncPulseId: store.syncPulseId,
                            syncPulseDirection: store.syncPulseDirection
                        )
                    }
                    .buttonStyle(RowePressScaleStyle())
                    .matchedTransitionSource(id: "settings-avatar", in: zoomNamespace)

                    Spacer()

                    HStack(spacing: 14) {
                        Menu {
                            Toggle("Show Completed", isOn: $showCompleted)
                            Toggle("Show Previous Days", isOn: $showPreviousDays)
                            Button("Add Task", systemImage: "plus") { onOpenQuickAdd(nil) }
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
                    .tint(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .roweIOSGlassCapsule(interactive: true)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                if mode == .calendar {
                    // Locked behind a gentle pull-down scroll (26pt–85pt); auto-hides when switching tabs
                    if isPreviousDaysRevealed || showPreviousDays {
                        Button {
                            IOSHaptics.shared.tap()
                            withAnimation(.easeInOut(duration: 0.22)) {
                                showPreviousDays.toggle()
                                if !showPreviousDays { isPreviousDaysRevealed = false }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 12))
                                Text(showPreviousDays ? "Hide Previous Days" : "Show Previous Days")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    VStack(alignment: .leading, spacing: 34) {
                        ForEach(visibleDays, id: \.self) { day in
                            daySection(for: day)
                                .transition(.opacity)
                        }
                    }
                } else {
                    allTasksBody
                }
            }
            .padding(.bottom, 120)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, adjustedOffset in
            guard mode == .calendar else { return }
            let pulled = max(0, -adjustedOffset)
            if pulled >= 26 && pulled < 85 && !isPreviousDaysRevealed && !showPreviousDays {
                IOSHaptics.shared.tap()
                withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
                    isPreviousDaysRevealed = true
                }
            }
        }
        .onDisappear {
            isPreviousDaysRevealed = false
            showPreviousDays = false
        }
        .iosPullDownToSearch(isPresented: $store.isQuickOpenPresented, reduceMotion: reduceMotion)
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func daySection(for day: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)
        let isTomorrow = cal.isDateInTomorrow(day)
        let isYesterday = cal.isDateInYesterday(day)

        let dayTasks = allTasks.filter { item in
            if let sched = item.block.task?.scheduleDate {
                return cal.isDate(sched, inSameDayAs: day)
            }
            return isToday
        }

        let pendingTasks = dayTasks.filter {
            ($0.block.task?.state ?? .pending) == .pending || lingeringTaskIds.contains($0.block.id)
        }
        let finishedTasks = dayTasks.filter {
            ($0.block.task?.state ?? .pending) != .pending && !lingeringTaskIds.contains($0.block.id)
        }
        let showDayCompleted = showCompleted || expandedCompletedDays.contains(day)

        let monthDay = day.formatted(.dateTime.month(.abbreviated).day())
        let weekday = day.formatted(.dateTime.weekday(.wide))

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        if isToday {
                            Text(monthDay)
                                .font(.system(size: 28, weight: .bold))
                            HStack(spacing: 6) {
                                Text("Today")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(selectedAccent)
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
                                } else if isYesterday {
                                    Text("Yesterday")
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
                        onOpenQuickAdd(day)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                }

                // Subtle hairline separator matching Craft Calendar
                Divider()
                    .opacity(0.28)
            }
            .padding(.horizontal, 18)

            if !pendingTasks.isEmpty {
                VStack(spacing: 2) {
                    ForEach(pendingTasks) { item in
                        IOSTaskRow(store: store, item: item, onSelectTask: {
                            IOSHaptics.shared.tap()
                            onEditTask(item)
                        }) { newState in
                            handleTaskStateChange(item: item, newState: newState)
                        }
                        .transition(.roweUnblur)
                    }
                }
                .animation(IOSTheme.craftSpring(reduceMotion: reduceMotion), value: pendingTasks.map(\.id))
            }

            // Show "View Completed" only when all tasks for that day are completed (or if user explicitly toggled it)
            if (pendingTasks.isEmpty && !finishedTasks.isEmpty) || (showDayCompleted && !finishedTasks.isEmpty) {
                Button {
                    IOSHaptics.shared.tap()
                    withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
                        if expandedCompletedDays.contains(day) {
                            expandedCompletedDays.remove(day)
                        } else {
                            expandedCompletedDays.insert(day)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.full")
                            .font(.system(size: 12))
                        Text(showDayCompleted ? "Hide Completed (\(finishedTasks.count))" : "View Completed (\(finishedTasks.count))")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.top, 2)
                }

                if showDayCompleted {
                    VStack(spacing: 2) {
                        ForEach(finishedTasks) { item in
                            IOSTaskRow(store: store, item: item, onSelectTask: {
                                IOSHaptics.shared.tap()
                                onEditTask(item)
                            }) { newState in
                                handleTaskStateChange(item: item, newState: newState)
                            }
                            .transition(.roweUnblur)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var allTasksBody: some View {
        let pending = allTasks.filter {
            ($0.block.task?.state ?? .pending) == .pending || lingeringTaskIds.contains($0.block.id)
        }
        let completed = allTasks.filter {
            ($0.block.task?.state ?? .pending) != .pending && !lingeringTaskIds.contains($0.block.id)
        }

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
                VStack(spacing: 14) {
                    RoweEmptyStateArtwork(kind: .tasksClear, accent: selectedAccent, size: 96)
                    Text("All Tasks Done")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("Tap + below to capture a new task.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ForEach(pending) { item in
                    IOSTaskRow(store: store, item: item, onSelectTask: {
                        IOSHaptics.shared.tap()
                        onEditTask(item)
                    }) { newState in
                        handleTaskStateChange(item: item, newState: newState)
                    }
                    .transition(.roweUnblur)
                }
                .animation(IOSTheme.craftSpring(reduceMotion: reduceMotion), value: pending.map(\.id))
            }

            if !completed.isEmpty {
                DisclosureGroup("Completed (\(completed.count))", isExpanded: $showCompleted) {
                    ForEach(completed) { item in
                        IOSTaskRow(store: store, item: item, onSelectTask: {
                            IOSHaptics.shared.tap()
                            onEditTask(item)
                        }) { newState in
                            handleTaskStateChange(item: item, newState: newState)
                        }
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
        }
    }

    private func handleTaskStateChange(item: ResolvedTaskItem, newState: TaskCompletionState) {
        let id = item.block.id
        lingerTimers[id]?.cancel()
        lingerTimers.removeValue(forKey: id)

        if newState == .pending {
            withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
                lingeringTaskIds.remove(id)
                store.setTaskState(docId: item.documentId, blockId: id, state: newState)
            }
            return
        }

        // Linger for 3s so double-tap red cross-out or quick undo never races with removal.
        lingeringTaskIds.insert(id)
        store.setTaskState(docId: item.documentId, blockId: id, state: newState)

        lingerTimers[id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            _ = withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
                lingeringTaskIds.remove(id)
            }
            lingerTimers.removeValue(forKey: id)
        }
    }
}

struct IOSTaskRow: View {
    @Bindable var store: WorkspaceStore
    let item: ResolvedTaskItem
    var onSelectTask: (() -> Void)? = nil
    var onStateChange: ((TaskCompletionState) -> Void)? = nil
    @State private var redFlash = false
    @State private var popScale: CGFloat = 1.0
    @State private var lastTapDate: Date = .distantPast

    private var state: TaskCompletionState {
        item.block.task?.state ?? .pending
    }

    private var selectedAccent: Color {
        Color(hex: store.settings.accentColor.hex)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        redFlash || state == .canceled
                            ? Color.red
                            : (state == .completed ? selectedAccent : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                redFlash || state == .canceled
                                    ? Color.red
                                    : (state == .completed ? Color.clear : Color.primary.opacity(0.35)),
                                lineWidth: 1.5
                            )
                    )
                if state == .completed && !redFlash {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else if state == .canceled || redFlash {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .scaleEffect(popScale)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle().inset(by: -10))
            .onTapGesture {
                let now = Date()
                if now.timeIntervalSince(lastTapDate) < 0.34 {
                    lastTapDate = .distantPast
                    triggerCrossOut()
                } else {
                    lastTapDate = now
                    triggerCompleteToggle()
                }
            }

            HStack(spacing: 8) {
                AnimatedStrikethroughText(
                    item.block.content.isEmpty ? "Untitled Task" : item.block.content,
                    isStruck: state != .pending,
                    strikeColor: state == .canceled ? Color.red.opacity(0.85) : .secondary,
                    font: .system(size: 16, weight: .medium),
                    lineLimit: 2,
                    reduceMotion: store.settings.reduceAnimations
                )

                Spacer(minLength: 6)

                if !(item.block.task?.notes.isEmpty ?? true) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                if let imgs = item.block.task?.attachedImagesBase64, !imgs.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "photo")
                            .font(.system(size: 10.5))
                        Text("\(imgs.count)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                }

                if item.block.task?.deadlineDate != nil {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                }

                if item.block.task?.reminderDate != nil {
                    Image(systemName: "alarm")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if item.block.task?.repeatRule != nil {
                    Image(systemName: "repeat")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                }

                if item.isInbox {
                    Text("Inbox")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelectTask?()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .contextMenu {
            Section {
                Menu("Schedule Task", systemImage: "calendar") {
                    Button("Today", systemImage: "sun.max") {
                        updateTaskMeta { $0.scheduleDate = Calendar.current.startOfDay(for: Date()) }
                    }
                    Button("Tomorrow", systemImage: "sunrise") {
                        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
                        updateTaskMeta { $0.scheduleDate = tomorrow }
                    }
                    Button("Next Week", systemImage: "calendar.badge.plus") {
                        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date()))
                        updateTaskMeta { $0.scheduleDate = nextWeek }
                    }
                    Divider()
                    Button("Clear Date", systemImage: "calendar.badge.minus", role: .destructive) {
                        updateTaskMeta { $0.scheduleDate = nil; $0.repeatRule = nil }
                    }
                }
                Button("Edit Task…", systemImage: "pencil") {
                    onSelectTask?()
                }
                Menu("Remind me", systemImage: "alarm") {
                    Button("In 1 Hour", systemImage: "clock") {
                        updateTaskMeta { $0.reminderDate = Date().addingTimeInterval(3600) }
                    }
                    Button("Tonight (6:00 PM)", systemImage: "moon") {
                        let base = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
                        updateTaskMeta { $0.reminderDate = base }
                    }
                    Button("Tomorrow (9:00 AM)", systemImage: "sunrise") {
                        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                        let base = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
                        updateTaskMeta { $0.reminderDate = base }
                    }
                    if item.block.task?.reminderDate != nil {
                        Divider()
                        Button("Clear Reminder", systemImage: "bell.slash", role: .destructive) {
                            updateTaskMeta { $0.reminderDate = nil }
                        }
                    }
                }
                Menu("Repeat", systemImage: "repeat") {
                    Button("None") {
                        updateTaskMeta { $0.repeatRule = nil }
                    }
                    ForEach(RepeatFrequency.allCases, id: \.self) { freq in
                        Button(freq.rawValue) {
                            let start = item.block.task?.scheduleDate ?? Calendar.current.startOfDay(for: Date())
                            let weekday = Calendar.current.component(.weekday, from: start)
                            updateTaskMeta {
                                $0.scheduleDate = $0.scheduleDate ?? start
                                $0.repeatRule = RepeatRule(frequency: freq, weekdayIndex: freq == .weekly ? weekday : nil, startDate: start)
                            }
                        }
                    }
                }
            }
            Section {
                Button(state == .completed ? "Mark as Incomplete" : "Mark as Completed", systemImage: "checkmark.square.fill") {
                    triggerCompleteToggle()
                }
                Button(state == .canceled ? "Uncancel Task" : "Mark as Cancelled", systemImage: "xmark.square.fill") {
                    triggerCrossOut()
                }
            }
            Section {
                Button("Copy", systemImage: "doc.on.doc") {
                    IOSHaptics.shared.tap()
                    UIPasteboard.general.string = item.block.content
                }
                Button("Delete Task", systemImage: "trash", role: .destructive) {
                    IOSHaptics.shared.errorBuzz()
                    store.deleteBlock(in: item.documentId, blockId: item.block.id)
                }
            }
        }
    }

    private func triggerPop() {
        withAnimation(.spring(response: 0.16, dampingFraction: 0.55)) {
            popScale = 1.18
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                popScale = 1.0
            }
        }
    }

    private func triggerCompleteToggle() {
        triggerPop()
        let next: TaskCompletionState = state == .pending ? .completed : .pending
        if next == .completed { IOSHaptics.shared.taskComplete() } else { IOSHaptics.shared.tap() }
        applyState(next)
    }

    private func triggerCrossOut() {
        triggerPop()
        IOSHaptics.shared.errorBuzz()
        withAnimation(.easeOut(duration: 0.1)) { redFlash = true }
        let next: TaskCompletionState = state == .canceled ? .pending : .canceled
        applyState(next)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { redFlash = false }
        }
    }

    private func updateTaskMeta(_ mutate: (inout TaskMetadata) -> Void) {
        IOSHaptics.shared.tap()
        store.updateBlock(in: item.documentId, blockId: item.block.id) { block in
            var meta = block.task ?? TaskMetadata(isInbox: item.isInbox)
            mutate(&meta)
            block.task = meta
        }
    }

    private func applyState(_ next: TaskCompletionState) {
        if let onStateChange {
            onStateChange(next)
        } else {
            store.setTaskState(docId: item.documentId, blockId: item.block.id, state: next)
        }
    }
}

/// Unified compact floating Task Composer (used for BOTH creating and editing tasks):
/// 1. Schedule date: Today, Tomorrow, or Open Calendar (inline graphical calendar)
/// 2. Cycling conversational prompt ("What dya wanna do today?")
/// 3. Repeat: Daily, Weekly, Monthly (plus Undo/Redo or Delete, and Add/Done)
struct IOSQuickAddTaskCard: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Bindable var store: WorkspaceStore
    let editingItem: ResolvedTaskItem?
    var onClose: () -> Void

    private static let prompts: [String] = [
        "What dya wanna do today?",
        "What's next on your mind?",
        "Something quick to knock out?",
        "What are we getting done?",
        "Capture it before it slips…"
    ]
    @MainActor private static var promptCursor: Int = 0

    @State private var text: String
    @State private var scheduleDate: Date
    @State private var repeatRule: RepeatRule?
    @State private var showCalendarPicker: Bool = false
    @State private var promptPlaceholder: String
    @State private var undoStack: [String] = []
    @State private var redoStack: [String] = []
    @State private var isApplyingHistory = false
    @FocusState private var isFocused: Bool

    init(
        store: WorkspaceStore,
        initialDate: Date = Calendar.current.startOfDay(for: Date()),
        editingItem: ResolvedTaskItem? = nil,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.editingItem = editingItem
        self.onClose = onClose
        let idx = Self.promptCursor % Self.prompts.count
        Self.promptCursor += 1
        self._promptPlaceholder = State(initialValue: Self.prompts[idx])

        if let item = editingItem {
            self._text = State(initialValue: item.block.content)
            self._scheduleDate = State(initialValue: item.block.task?.scheduleDate ?? Calendar.current.startOfDay(for: initialDate))
            self._repeatRule = State(initialValue: item.block.task?.repeatRule)
        } else {
            self._text = State(initialValue: "")
            self._scheduleDate = State(initialValue: Calendar.current.startOfDay(for: initialDate))
            self._repeatRule = State(initialValue: nil)
        }
    }

    private var isEditing: Bool { editingItem != nil }

    private var resolvedAccent: Color {
        let isDark: Bool = switch store.settings.appearanceMode {
        case .system: systemColorScheme == .dark
        case .light: false
        case .dark: true
        }
        if store.settings.accentColor == .graphite && isDark {
            return Color(hex: "#F3F4F6")
        }
        return Color(hex: store.settings.accentColor.hex)
    }

    private var dateLabel: String {
        if Calendar.current.isDateInToday(scheduleDate) { return "Today" }
        if Calendar.current.isDateInTomorrow(scheduleDate) { return "Tomorrow" }
        return scheduleDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private let allowedRepeats: [RepeatFrequency] = [.daily, .weekly, .monthly]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. Top bar: When to schedule (Today, Tomorrow, Open Calendar) + Close
            HStack {
                Menu {
                    Button("Today", systemImage: "sun.max") {
                        IOSHaptics.shared.tap()
                        scheduleDate = Calendar.current.startOfDay(for: Date())
                        withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            showCalendarPicker = false
                        }
                    }
                    Button("Tomorrow", systemImage: "sunrise") {
                        IOSHaptics.shared.tap()
                        scheduleDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                        withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            showCalendarPicker = false
                        }
                    }
                    Divider()
                    Button("Open Calendar…", systemImage: "calendar") {
                        IOSHaptics.shared.tap()
                        IOSKeyboard.dismiss()
                        isFocused = false
                        withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                            showCalendarPicker.toggle()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14))
                            .foregroundStyle(resolvedAccent)
                        Text(dateLabel)
                            .font(.system(size: 15, weight: .medium))
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
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
                        .contentShape(Circle())
                }
                .buttonStyle(RowePressScaleStyle())
            }

            // Inline graphical calendar view (matching macOS calendar popover)
            if showCalendarPicker {
                DatePicker(
                    "Schedule Date",
                    selection: $scheduleDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(resolvedAccent)
                .onChange(of: scheduleDate) { _, newDate in
                    IOSHaptics.shared.tap()
                    scheduleDate = Calendar.current.startOfDay(for: newDate)
                    withAnimation(IOSTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                        showCalendarPicker = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { isFocused = true }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            // 2. Task title with cycling conversational placeholder (no notes field)
            TextField(promptPlaceholder, text: $text, axis: .vertical)
                .focused($isFocused)
                .font(.system(size: 17, weight: .medium))
                .lineLimit(1...4)
                .submitLabel(.done)
                .onSubmit { saveAndClose() }
                .onChange(of: text) { oldValue, newValue in
                    guard !isApplyingHistory, oldValue != newValue else { return }
                    undoStack.append(oldValue)
                    if undoStack.count > 40 { undoStack.removeFirst() }
                    redoStack.removeAll()
                }

            // 3. Bottom row: Repeat (Daily / Weekly / Monthly), Undo/Delete, and Add/Done
            HStack(spacing: 10) {
                Menu {
                    if repeatRule != nil {
                        Button("Off", role: .destructive) {
                            IOSHaptics.shared.tap()
                            repeatRule = nil
                        }
                        Divider()
                    }
                    ForEach(allowedRepeats, id: \.self) { freq in
                        Button {
                            IOSHaptics.shared.tap()
                            let weekday = Calendar.current.component(.weekday, from: scheduleDate)
                            repeatRule = RepeatRule(
                                frequency: freq,
                                weekdayIndex: freq == .weekly ? weekday : nil,
                                startDate: scheduleDate
                            )
                        } label: {
                            Label(freq.rawValue, systemImage: repeatRule?.frequency == freq ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "repeat")
                            .font(.system(size: 13.5, weight: .medium))
                        if let freq = repeatRule?.frequency {
                            Text(freq.rawValue)
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                    }
                    .foregroundStyle(repeatRule != nil ? resolvedAccent : .secondary)
                    .padding(.horizontal, repeatRule != nil ? 11 : 0)
                    .frame(minWidth: 32, minHeight: 32)
                    .background(
                        Capsule().fill(repeatRule != nil ? resolvedAccent.opacity(0.15) : Color.primary.opacity(0.06))
                    )
                }

                if isEditing, let item = editingItem {
                    Button(role: .destructive) {
                        IOSHaptics.shared.errorBuzz()
                        store.deleteBlock(in: item.documentId, blockId: item.block.id)
                        onClose()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.red.opacity(0.10)))
                    }
                    .buttonStyle(RowePressScaleStyle())
                } else {
                    Button {
                        guard let prev = undoStack.popLast() else { return }
                        IOSHaptics.shared.tap()
                        isApplyingHistory = true
                        redoStack.append(text)
                        text = prev
                        DispatchQueue.main.async { isApplyingHistory = false }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(undoStack.isEmpty ? Color.secondary.opacity(0.35) : .primary)
                            .frame(width: 28, height: 28)
                    }
                    .disabled(undoStack.isEmpty)
                    .buttonStyle(RowePressScaleStyle())

                    Button {
                        guard let next = redoStack.popLast() else { return }
                        IOSHaptics.shared.tap()
                        isApplyingHistory = true
                        undoStack.append(text)
                        text = next
                        DispatchQueue.main.async { isApplyingHistory = false }
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(redoStack.isEmpty ? Color.secondary.opacity(0.35) : .primary)
                            .frame(width: 28, height: 28)
                    }
                    .disabled(redoStack.isEmpty)
                    .buttonStyle(RowePressScaleStyle())
                }

                Spacer()

                Button {
                    saveAndClose()
                } label: {
                    Text(isEditing ? "Done" : "Add")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(store.settings.accentColor == .graphite ? Color(uiColor: .systemBackground) : .white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(resolvedAccent))
                        .contentShape(Capsule())
                }
                .buttonStyle(RowePressScaleStyle())
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            if !showCalendarPicker { isFocused = true }
        }
        .roweIOSGlassRoundedRect(radius: 24, interactive: true)
        .iosDragToDismiss(onDismiss: onClose)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true }
        }
    }

    private func saveAndClose() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        IOSHaptics.shared.taskComplete()

        if let item = editingItem {
            store.updateBlock(in: item.documentId, blockId: item.block.id) { block in
                block.content = trimmed
                var meta = block.task ?? TaskMetadata(isInbox: item.isInbox)
                meta.scheduleDate = scheduleDate
                meta.repeatRule = repeatRule
                block.task = meta
            }
        } else {
            _ = store.addInboxTask(
                title: trimmed,
                scheduleDate: scheduleDate,
                repeatRule: repeatRule
            )
        }
        onClose()
    }
}
