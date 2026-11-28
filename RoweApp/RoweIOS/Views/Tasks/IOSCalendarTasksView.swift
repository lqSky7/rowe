import PhotosUI
import SwiftUI
import UIKit
import RoweCore

enum IOSTaskViewMode {
    case calendar
    case allTasks
}

/// iOS Calendar & Tasks view:
/// - Date-grouped timeline with crisp hairline separators under every day header
/// - Progressive blur fade on top and bottom edges
/// - Bolder, easy-to-read multiline task titles with red-cross glow and accent tick glow
/// - "View Completed" shown only once all tasks for a day are completed
/// - "Show Previous Days" cleanly tucked inside the ••• menu (no accidental down-scroll reveal)
/// - Unified floating Task Composer supporting Today/Tomorrow/Calendar, Daily/Weekly/Monthly repeat, and pasting/attaching photos.
struct IOSCalendarTasksView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: WorkspaceStore
    let mode: IOSTaskViewMode
    let zoomNamespace: Namespace.ID
    var flightCoordinator: IOSTaskFlightCoordinator? = nil
    var downsyncWaveCoordinator: IOSDownsyncWaveCoordinator? = nil
    var onOpenSettings: () -> Void
    var onOpenQuickAdd: (Date?) -> Void
    var onEditTask: (ResolvedTaskItem) -> Void

    @State private var showCompleted: Bool = false
    @State private var showPreviousDays: Bool = false
    @State private var expandedCompletedDays: Set<Date> = []
    @State private var lingeringTaskIds: Set<String> = []
    @State private var lingerTimers: [String: Task<Void, Never>] = [:]

    private var reduceMotion: Bool {
        store.settings.reduceAnimations
    }

    private var selectedAccent: Color {
        Color(hex: store.settings.accentColor.resolvedHex(isDark: colorScheme == .dark))
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
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Top bar (avatar + clean ••• menu, no unused notification bell)
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

                        Menu {
                            Toggle("Show Completed", isOn: $showCompleted)
                            Toggle("Show Previous Days", isOn: $showPreviousDays)
                            Divider()
                            Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                                IOSHaptics.shared.tap()
                                store.triggerManualSync()
                            }
                            Button("Add Task", systemImage: "plus") { onOpenQuickAdd(nil) }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 38, height: 38)
                                .roweIOSGlass(in: Circle(), interactive: true)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                    if mode == .calendar {
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
                .padding(.bottom, 124)
            }
            .iosPullDownToSearch(isPresented: $store.isQuickOpenPresented, reduceMotion: reduceMotion)
            .scrollDismissesKeyboard(.interactively)

            // Clean progressive edge fade on top and bottom (zero gray haze in Dark Mode)
            VStack {
                IOSProgressiveBlurEdge(edge: .top, height: 56)
                Spacer()
                IOSProgressiveBlurEdge(edge: .bottom, height: 88)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .onDisappear {
            showPreviousDays = false
        }
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

                Divider()
                    .opacity(0.28)
            }
            .padding(.horizontal, 18)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                flightCoordinator?.reportDaySectionFrame(frame, for: day)
            }

            if !pendingTasks.isEmpty {
                VStack(spacing: 2) {
                    ForEach(pendingTasks) { item in
                        let isDownsynced = downsyncWaveCoordinator?.highlightedTaskIds.contains(item.block.id) == true
                        let isHiddenForReveal = downsyncWaveCoordinator?.shouldHidePendingReveal(item.block.id) == true
                        let isHidden = (flightCoordinator?.shouldHideRow(item.block.id) == true) || isHiddenForReveal
                        IOSTaskRow(store: store, item: item, onSelectTask: {
                            IOSHaptics.shared.tap()
                            onEditTask(item)
                        }) { newState in
                            handleTaskStateChange(item: item, newState: newState)
                        }
                        .opacity(isHidden ? 0 : 1)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .global)
                        } action: { frame in
                            flightCoordinator?.reportRowFrame(frame, for: item.block.id)
                        }
                        .transition((isDownsynced || isHiddenForReveal) ? .opacity : .roweUnblur)
                    }
                }
                .animation(IOSTheme.craftSpring(reduceMotion: reduceMotion), value: pendingTasks.map(\.id))
            }

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
                    let isDownsynced = downsyncWaveCoordinator?.highlightedTaskIds.contains(item.block.id) == true
                    let isHiddenForReveal = downsyncWaveCoordinator?.shouldHidePendingReveal(item.block.id) == true
                    let isHidden = (flightCoordinator?.shouldHideRow(item.block.id) == true) || isHiddenForReveal
                    IOSTaskRow(store: store, item: item, onSelectTask: {
                        IOSHaptics.shared.tap()
                        onEditTask(item)
                    }) { newState in
                        handleTaskStateChange(item: item, newState: newState)
                    }
                    .opacity(isHidden ? 0 : 1)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        flightCoordinator?.reportRowFrame(frame, for: item.block.id)
                    }
                    .transition((isDownsynced || isHiddenForReveal) ? .opacity : .roweUnblur)
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
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: WorkspaceStore
    let item: ResolvedTaskItem
    var onSelectTask: (() -> Void)? = nil
    var onStateChange: ((TaskCompletionState) -> Void)? = nil
    @State private var redFlash = false
    @State private var accentFlash = false
    @State private var popScale: CGFloat = 1.0
    @State private var lastTapDate: Date = .distantPast

    private var state: TaskCompletionState {
        item.block.task?.state ?? .pending
    }

    private var selectedAccent: Color {
        Color(hex: store.settings.accentColor.resolvedHex(isDark: colorScheme == .dark))
    }

    private var checkboxGlowColor: Color {
        if redFlash { return Color.red.opacity(0.50) }
        if accentFlash { return selectedAccent.opacity(0.50) }
        if state == .canceled { return Color.red.opacity(0.24) }
        if state == .completed { return selectedAccent.opacity(0.24) }
        return .clear
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(checkboxGlowColor)
                    .frame(width: 24, height: 24)
                    .blur(radius: 4)
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(
                        redFlash || state == .canceled
                            ? Color.red
                            : (state == .completed ? selectedAccent : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                            .strokeBorder(
                                redFlash || state == .canceled
                                    ? Color.red
                                    : (state == .completed ? Color.clear : Color.primary.opacity(0.35)),
                                lineWidth: 1.4
                            )
                    )
                if state == .completed && !redFlash {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(store.settings.accentColor.prefersDarkForeground(isDark: colorScheme == .dark) ? Color.black.opacity(0.88) : Color.white)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else if state == .canceled || redFlash {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.16), value: redFlash)
            .animation(.easeOut(duration: 0.16), value: accentFlash)
            .scaleEffect(popScale)
            .frame(width: 19, height: 19)
            // Generous tap padding above/below/left, but tight 3pt trailing margin so tapping near text never triggers completion
            .padding(.top, 9)
            .padding(.bottom, 9)
            .padding(.leading, 9)
            .padding(.trailing, 3)
            .contentShape(Rectangle())
            .padding(.top, -9)
            .padding(.bottom, -9)
            .padding(.leading, -9)
            .padding(.trailing, -3)
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
                }
                Button("Edit Task…", systemImage: "pencil") {
                    onSelectTask?()
                }
                Menu("Repeat", systemImage: "repeat") {
                    Button("Off") {
                        updateTaskMeta { $0.repeatRule = nil }
                    }
                    ForEach([RepeatFrequency.daily, .weekly, .monthly], id: \.self) { freq in
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
        if next == .completed {
            IOSHaptics.shared.taskComplete()
            withAnimation(.easeOut(duration: 0.08)) { accentFlash = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 340_000_000)
                withAnimation(.easeInOut(duration: 0.24)) { accentFlash = false }
            }
        } else {
            IOSHaptics.shared.tap()
        }
        applyState(next)
    }

    private func triggerCrossOut() {
        triggerPop()
        IOSHaptics.shared.errorBuzz()
        withAnimation(.easeOut(duration: 0.08)) { redFlash = true }
        let next: TaskCompletionState = state == .canceled ? .pending : .canceled
        applyState(next)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 340_000_000)
            withAnimation(.easeInOut(duration: 0.24)) { redFlash = false }
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
/// 3. Repeat: Daily, Weekly, Monthly + Paste/Attach Photos (matching Mac)
private struct OptionalComposerGlassModifier: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.roweIOSGlassRoundedRect(radius: 24, interactive: false)
        } else {
            content
        }
    }
}

struct IOSQuickAddTaskCard: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Bindable var store: WorkspaceStore
    let editingItem: ResolvedTaskItem?
    var embedGlassBackground: Bool = true
    var immediateFocus: Bool = true
    var onCreatedTaskForFlight: ((ResolvedTaskItem, CGRect, CGRect) -> Void)? = nil
    var onOpenDayDocument: ((String) -> Void)? = nil
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
    @State private var attachedImagesBase64: [String]
    @State private var showCalendarPicker: Bool = false
    @State private var showPhotosPicker: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var previewImageIndex: Int? = nil
    @State private var didCopyPreviewImage: Bool = false
    @State private var cardFrame: CGRect = .zero
    @State private var textFieldFrame: CGRect = .zero
    @State private var dragOffsetY: CGFloat = 0
    @State private var promptPlaceholder: String
    @State private var undoStack: [String] = []
    @State private var redoStack: [String] = []
    @State private var isApplyingHistory = false
    @FocusState private var isFocused: Bool

    init(
        store: WorkspaceStore,
        initialDate: Date = Calendar.current.startOfDay(for: Date()),
        editingItem: ResolvedTaskItem? = nil,
        embedGlassBackground: Bool = true,
        immediateFocus: Bool = true,
        onCreatedTaskForFlight: ((ResolvedTaskItem, CGRect, CGRect) -> Void)? = nil,
        onOpenDayDocument: ((String) -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.editingItem = editingItem
        self.embedGlassBackground = embedGlassBackground
        self.immediateFocus = immediateFocus
        self.onCreatedTaskForFlight = onCreatedTaskForFlight
        self.onOpenDayDocument = onOpenDayDocument
        self.onClose = onClose
        let idx = Self.promptCursor % Self.prompts.count
        Self.promptCursor += 1
        self._promptPlaceholder = State(initialValue: Self.prompts[idx])

        if let item = editingItem {
            self._text = State(initialValue: item.block.content)
            self._scheduleDate = State(initialValue: item.block.task?.scheduleDate ?? Calendar.current.startOfDay(for: initialDate))
            self._repeatRule = State(initialValue: item.block.task?.repeatRule)
            self._attachedImagesBase64 = State(initialValue: item.block.task?.attachedImagesBase64 ?? [])
        } else {
            self._text = State(initialValue: "")
            self._scheduleDate = State(initialValue: Calendar.current.startOfDay(for: initialDate))
            self._repeatRule = State(initialValue: nil)
            self._attachedImagesBase64 = State(initialValue: [])
        }
    }

    private var isEditing: Bool { editingItem != nil }

    private var isDarkMode: Bool {
        switch store.settings.appearanceMode {
        case .system: systemColorScheme == .dark
        case .light: false
        case .dark: true
        }
    }

    private var resolvedAccent: Color {
        Color(hex: store.settings.accentColor.resolvedHex(isDark: isDarkMode))
    }

    private var dateLabel: String {
        if Calendar.current.isDateInToday(scheduleDate) { return "Today" }
        if Calendar.current.isDateInTomorrow(scheduleDate) { return "Tomorrow" }
        return scheduleDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private let allowedRepeats: [RepeatFrequency] = [.daily, .weekly, .monthly]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Capsule()
                    .fill(Color.primary.opacity(0.20))
                    .frame(width: 34, height: 4)
                Spacer()
            }
            .padding(.top, -6)

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
                    isFocused = true
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            // 2. Task title with cycling conversational placeholder
            TextField(promptPlaceholder, text: $text, axis: .vertical)
                .focused($isFocused)
                .font(.system(size: 17, weight: .medium))
                .lineLimit(1...4)
                .submitLabel(.done)
                .onSubmit { saveAndClose() }
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    textFieldFrame = frame
                }
                .onChange(of: text) { oldValue, newValue in
                    guard !isApplyingHistory, oldValue != newValue else { return }
                    undoStack.append(oldValue)
                    if undoStack.count > 40 { undoStack.removeFirst() }
                    redoStack.removeAll()
                }

            if !attachedImagesBase64.isEmpty {
                attachedPhotosStrip
            }

            composerToolbar
        }
        .padding(18)
        .modifier(OptionalComposerGlassModifier(enabled: embedGlassBackground))
        .offset(y: dragOffsetY)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    let dy = value.translation.height
                    dragOffsetY = dy > 0 ? dy : dy * 0.18
                }
                .onEnded { value in
                    let dy = value.translation.height
                    let predicted = value.predictedEndTranslation.height
                    if dy > 52 || predicted > 105 {
                        IOSHaptics.shared.tap()
                        dragOffsetY = 0
                        onClose()
                    } else {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                            dragOffsetY = 0
                        }
                    }
                }
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            cardFrame = frame
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhotoItem, matching: .images)
        .sheet(isPresented: Binding(
            get: { previewImageIndex != nil },
            set: { if !$0 { previewImageIndex = nil; didCopyPreviewImage = false } }
        )) {
            if let idx = previewImageIndex, attachedImagesBase64.indices.contains(idx) {
                imagePreviewSheet(index: idx, base64: attachedImagesBase64[idx])
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   let encoded = Self.encodeCompressedBase64(img) {
                    await MainActor.run {
                        IOSHaptics.shared.tap()
                        attachedImagesBase64.append(encoded)
                        selectedPhotoItem = nil
                    }
                }
            }
        }
        .onAppear {
            isFocused = true
        }
    }

    private var attachedPhotosStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachedImagesBase64.enumerated()), id: \.offset) { idx, b64 in
                    HStack(spacing: 5) {
                        Button {
                            IOSHaptics.shared.tap()
                            didCopyPreviewImage = false
                            previewImageIndex = idx
                        } label: {
                            HStack(spacing: 5) {
                                if let data = Data(base64Encoded: b64), let uiImg = UIImage(data: data) {
                                    Image(uiImage: uiImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 20, height: 20)
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                } else {
                                    Image(systemName: "photo")
                                        .font(.system(size: 11))
                                }
                                Text("#image \(idx + 1)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            IOSHaptics.shared.tap()
                            attachedImagesBase64.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .contextMenu {
                        Button("Copy Image", systemImage: "doc.on.doc") {
                            copyImage(at: idx)
                        }
                        Button("Preview", systemImage: "eye") {
                            didCopyPreviewImage = false
                            previewImageIndex = idx
                        }
                        Divider()
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            IOSHaptics.shared.tap()
                            attachedImagesBase64.remove(at: idx)
                        }
                    }
                }
            }
        }
    }

    private var composerToolbar: some View {
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

            Menu {
                Button("Paste Photo from Clipboard", systemImage: "doc.on.clipboard") {
                    pasteClipboardImage()
                }
                Button("Choose from Photos…", systemImage: "photo.on.rectangle") {
                    IOSHaptics.shared.tap()
                    showPhotosPicker = true
                }
            } label: {
                Image(systemName: attachedImagesBase64.isEmpty ? "photo.badge.plus" : "photo.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(attachedImagesBase64.isEmpty ? .secondary : resolvedAccent)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(attachedImagesBase64.isEmpty ? Color.primary.opacity(0.06) : resolvedAccent.opacity(0.15))
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

            Text(isEditing ? "Done" : "Add")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(store.settings.accentColor.prefersDarkForeground(isDark: isDarkMode) ? Color.black : .white)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(Capsule().fill(resolvedAccent))
                .opacity((text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedImagesBase64.isEmpty && !isEditing) ? 0.55 : 1.0)
                .contentShape(Capsule())
                .onTapGesture {
                    saveAndClose()
                }
                .onLongPressGesture(minimumDuration: 0.45) {
                    IOSHaptics.shared.snap()
                    let targetDocId: String
                    if let item = editingItem {
                        targetDocId = item.documentId
                    } else {
                        targetDocId = store.ensureTaskDayDocument(for: scheduleDate).id
                    }
                    onOpenDayDocument?(targetDocId)
                }
        }
    }

    @ViewBuilder
    private func imagePreviewSheet(index: Int, base64: String) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let data = Data(base64Encoded: base64), let uiImg = UIImage(data: data) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("Image Unavailable", systemImage: "photo")
                }

                HStack(spacing: 12) {
                    Button {
                        copyImage(at: index)
                        withAnimation(.easeInOut(duration: 0.16)) {
                            didCopyPreviewImage = true
                        }
                    } label: {
                        Label(didCopyPreviewImage ? "Copied" : "Copy Image", systemImage: didCopyPreviewImage ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(resolvedAccent))
                            .foregroundStyle(isDarkMode && store.settings.accentColor == .graphite ? Color.black : .white)
                    }
                    .buttonStyle(RowePressScaleStyle())

                    Button(role: .destructive) {
                        IOSHaptics.shared.tap()
                        if attachedImagesBase64.indices.contains(index) {
                            attachedImagesBase64.remove(at: index)
                        }
                        previewImageIndex = nil
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.red.opacity(0.14)))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(RowePressScaleStyle())
                }
            }
            .padding(20)
            .navigationTitle("#image \(index + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { previewImageIndex = nil }
                }
            }
        }
    }

    private func copyImage(at index: Int) {
        guard attachedImagesBase64.indices.contains(index),
              let data = Data(base64Encoded: attachedImagesBase64[index]),
              let img = UIImage(data: data) else {
            IOSHaptics.shared.errorBuzz()
            return
        }
        IOSHaptics.shared.taskComplete()
        UIPasteboard.general.image = img
    }

    private func pasteClipboardImage() {
        guard let img = UIPasteboard.general.image,
              let encoded = Self.encodeCompressedBase64(img) else {
            IOSHaptics.shared.errorBuzz()
            return
        }
        IOSHaptics.shared.tap()
        attachedImagesBase64.append(encoded)
    }

    private static func encodeCompressedBase64(_ image: UIImage, maxDimension: CGFloat = 900) -> String? {
        let orig = image.size
        guard orig.width > 0, orig.height > 0 else { return nil }
        let scale = min(1.0, maxDimension / max(orig.width, orig.height))
        let target = CGSize(width: round(orig.width * scale), height: round(orig.height * scale))
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.78)?.base64EncodedString()
    }

    private func saveAndClose() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachedImagesBase64.isEmpty else { return }
        let finalTitle = trimmed.isEmpty ? "Image Task" : trimmed

        if let item = editingItem {
            store.updateBlock(in: item.documentId, blockId: item.block.id) { block in
                block.content = finalTitle
                var meta = block.task ?? TaskMetadata(isInbox: item.isInbox)
                meta.scheduleDate = scheduleDate
                meta.repeatRule = repeatRule
                meta.attachedImagesBase64 = attachedImagesBase64
                block.task = meta
            }
            IOSHaptics.shared.taskComplete()
            onClose()
        } else {
            let created = store.addInboxTask(
                title: finalTitle,
                scheduleDate: scheduleDate,
                repeatRule: repeatRule,
                attachedImagesBase64: attachedImagesBase64
            )
            if !store.settings.reduceAnimations && store.settings.crazyTaskComposeAnimation, let onCreatedTaskForFlight {
                IOSHaptics.shared.tap()
                onCreatedTaskForFlight(created, textFieldFrame, cardFrame)
            } else {
                IOSHaptics.shared.taskComplete()
                onClose()
            }
        }
    }
}
