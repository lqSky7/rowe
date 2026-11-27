import SwiftUI
import RoweCore

struct CalendarTasksView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: WorkspaceStore
    var flightCoordinator: MacTaskFlightCoordinator? = nil
    var downsyncWaveCoordinator: MacDownsyncWaveCoordinator? = nil
    @State private var showTasks = true
    @State private var showEvents = false
    @State private var showPreviousDays = false
    @State private var expandedCompletedDays: Set<Date> = []
    @State private var lingeringTaskIds: Set<String> = []
    @State private var lingerTimers: [String: Task<Void, Never>] = [:]
    @State private var dropTargetedTaskId: String?
    @State private var dropTargetedDay: Date?
    @State private var showTodayCelebration = false
    @State private var celebrationBurstProgress: CGFloat = 0

    private let calendar = Calendar.current

    private var reduceMotion: Bool {
        store.settings.reduceAnimations
    }

    private var selectedAccent: Color {
        Color(hex: store.settings.accentColor.resolvedHex(isDark: colorScheme == .dark))
    }

    private var dullAccent: Color {
        Color(hex: store.settings.accentColor.dullHex)
    }

    private var visibleDays: [Date] {
        let today = calendar.startOfDay(for: Date())
        let startOffset = showPreviousDays ? -3 : 0
        return (startOffset...6).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.leading, store.isLeftSidebarVisible ? 20 : 58)
                .padding(.trailing, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .animation(CraftTheme.craftSpring(reduceMotion: reduceMotion), value: store.isLeftSidebarVisible)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button {
                        HapticsManager.shared.tap()
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showPreviousDays.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11.5))
                            Text(showPreviousDays ? "Hide Previous Days" : "Show Previous Days")
                                .font(.system(size: 12.5))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transaction { $0.animation = nil }
                    .padding(.leading, 18)

                    let allTasks = store.allTasks()
                    ForEach(visibleDays, id: \.self) { day in
                        let dayTasks = allTasks.filter { item in
                            guard let sched = item.block.task?.scheduleDate else { return false }
                            return calendar.isDate(sched, inSameDayAs: day)
                        }
                        dayCard(for: day, tasks: dayTasks)
                    }
                }
                .frame(maxWidth: 820)
                .padding(.horizontal, 36)
                .padding(.top, 8)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            GlassCircleButton(systemImage: "plus", helpText: "New Task (⌘L / ⌘J)") {
                let today = calendar.startOfDay(for: Date())
                withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                    store.activeTaskEditor = .create(defaultDate: today)
                }
            }

            Text("Calendar")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            HStack(spacing: 6) {
                filterToggleChip(title: "Tasks", isOn: $showTasks)
                filterToggleChip(title: "Events", isOn: $showEvents)
            }
            .padding(4)
            .roweGlassCapsule(interactive: true)

            GlassCircleButton(systemImage: "magnifyingglass", helpText: "Global Search (⌘K)") {
                withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                    store.isQuickOpenPresented = true
                }
            }
        }
    }

    private func filterToggleChip(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            HapticsManager.shared.toggle()
            withAnimation(CraftTheme.microSpring(reduceMotion: reduceMotion)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isOn.wrappedValue ? selectedAccent : .secondary)
                Text(title)
                    .font(.system(size: 12.5, weight: isOn.wrappedValue ? .medium : .regular))
            }
            .foregroundStyle(isOn.wrappedValue ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isOn.wrappedValue ? dullAccent.opacity(0.24) : Color.clear))
        }
        .buttonStyle(RowePressScaleButtonStyle())
    }

    private func dayCard(for day: Date, tasks: [ResolvedTaskItem]) -> some View {
        let isToday = calendar.isDateInToday(day)
        let showCompleted = expandedCompletedDays.contains(day)
        var seenIds: Set<String> = []
        let uniqueTasks = tasks.filter { seenIds.insert($0.block.id).inserted }
        let pendingTasks = uniqueTasks.filter {
            ($0.block.task?.state ?? .pending) == .pending || (!showCompleted && lingeringTaskIds.contains($0.block.id))
        }
        let pendingIdSet = Set(pendingTasks.map(\.block.id))
        let finishedTasks = uniqueTasks.filter {
            ($0.block.task?.state ?? .pending) != .pending && !pendingIdSet.contains($0.block.id)
        }
        let isDayDropTarget = dropTargetedDay == day

        return HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayNumberTitle(day))
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(isToday ? selectedAccent : .primary)
                if let relative = relativeDayLabel(day) {
                    Text(relative)
                        .font(.system(size: 13, weight: isToday ? .semibold : .medium))
                        .foregroundStyle(isToday ? selectedAccent : .secondary)
                }
                Text(weekdayName(day))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 112, alignment: .topLeading)
            .frame(minHeight: isToday ? 160 : 88)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(dullAccent.opacity(isToday ? 0.22 : 0.10))
            )

            VStack(alignment: .leading, spacing: 10) {
                if showTasks {
                    ForEach(pendingTasks) { item in
                        let isDownsynced = downsyncWaveCoordinator?.highlightedTaskIds.contains(item.block.id) == true
                        calendarTaskRow(item, day: day, isDownsynced: isDownsynced)
                            .id("pending-\(item.block.id)")
                            .transition(isDownsynced ? .opacity : .roweUnblur)
                    }

                    if (pendingTasks.isEmpty && !finishedTasks.isEmpty) || showCompleted {
                        Button {
                            HapticsManager.shared.tap()
                            withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                                if showCompleted {
                                    expandedCompletedDays.remove(day)
                                } else {
                                    expandedCompletedDays.insert(day)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "tray.full")
                                    .font(.system(size: 11.5))
                                Text(showCompleted ? "Hide Completed (\(finishedTasks.count))" : "View Completed (\(finishedTasks.count))")
                                    .font(.system(size: 12.5, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        }
                        .buttonStyle(.plain)

                        if showCompleted {
                            ForEach(finishedTasks) { item in
                                calendarTaskRow(item, day: day)
                                    .id("done-\(item.block.id)")
                                    .transition(.roweUnblur)
                            }
                        }
                    }

                    if isToday {
                        GlassPillButton("Add Task", systemImage: "checkmark.square", tint: selectedAccent) {
                            withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                                store.activeTaskEditor = .create(defaultDate: day)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .animation(CraftTheme.craftSpring(reduceMotion: reduceMotion), value: pendingTasks.map(\.id))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, isToday ? 18 : 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isToday ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            isDayDropTarget ? selectedAccent.opacity(0.75) : Color.clear,
                            lineWidth: isDayDropTarget ? 1.5 : 0
                        )
                )
                .shadow(color: isToday ? .black.opacity(0.07) : .clear, radius: 18, y: 6)
        )
        .animation(CraftTheme.hoverEase(reduceMotion: reduceMotion), value: isDayDropTarget)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("macWindowSpace"))
        } action: { frame in
            flightCoordinator?.reportDaySectionFrame(frame, for: day)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, raw.hasPrefix("task:") else { return false }
            let blockId = String(raw.dropFirst("task:".count))
            HapticsManager.shared.boundarySnap()
            withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                store.reorderOrRescheduleTask(sourceBlockId: blockId, targetBlockId: nil, targetDay: day)
            }
            dropTargetedDay = nil
            return true
        } isTargeted: { targeted in
            if targeted && dropTargetedDay != day {
                HapticsManager.shared.tap()
            }
            dropTargetedDay = targeted ? day : (dropTargetedDay == day ? nil : dropTargetedDay)
        }
    }

    private var todayCelebrationBanner: some View {
        ZStack(alignment: .leading) {
            // Subtle radial particle burst on clear
            if !reduceMotion && celebrationBurstProgress > 0 && celebrationBurstProgress < 1 {
                ForEach(0..<10, id: \.self) { idx in
                    let angle = Double(idx) * (360.0 / 10.0) * .pi / 180.0
                    let radius = 16.0 + celebrationBurstProgress * 34.0
                    Circle()
                        .fill(idx.isMultiple(of: 2) ? selectedAccent : Color.green)
                        .frame(width: 4.5, height: 4.5)
                        .offset(x: 18 + cos(angle) * radius, y: sin(angle) * radius)
                        .opacity(Double(1.0 - celebrationBurstProgress))
                }
                .allowsHitTesting(false)
            }

            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(selectedAccent)
                Text("All clear for today")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func calendarTaskRow(_ item: ResolvedTaskItem, day: Date, isDownsynced: Bool = false) -> some View {
        let state = item.block.task?.state ?? .pending
        let isDone = state != .pending
        let images = item.block.task?.attachedImagesBase64 ?? []
        let isDropTarget = dropTargetedTaskId == item.block.id

        return VStack(alignment: .leading, spacing: 0) {
            if isDropTarget {
                Capsule()
                    .fill(selectedAccent)
                    .frame(height: 2.5)
                    .padding(.bottom, 5)
                    .transition(.opacity)
            }

            HStack(spacing: 8) {
                TaskCheckboxControl(state: state) { newState in
                    handleTaskStateChange(item: item, newState: newState, day: day)
                }

                // Keep .draggable strictly on the title/badges area so micro-movements while clicking
                // TaskCheckboxControl never get swallowed as cancelled drags.
                HStack(spacing: 8) {
                    AnimatedStrikethroughText(
                        item.block.content,
                        isStruck: isDone && store.settings.completedTaskStyle == .strikethrough,
                        font: .system(size: 13.5, weight: .medium),
                        lineLimit: 2,
                        reduceMotion: reduceMotion
                    )
                    .onTapGesture {
                        HapticsManager.shared.tap()
                        if !reduceMotion && store.settings.crazyTaskComposeAnimation, let fc = flightCoordinator {
                            fc.launchOpenForEdit(
                                item: item,
                                accentColor: selectedAccent,
                                isDarkMode: colorScheme == .dark
                            ) {
                                var noAnim = Transaction()
                                noAnim.disablesAnimations = true
                                withTransaction(noAnim) {
                                    store.activeTaskEditor = .edit(item)
                                }
                            }
                        } else {
                            withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                                store.activeTaskEditor = .edit(item)
                            }
                        }
                    }

                    ForEach(Array(images.enumerated()), id: \.offset) { idx, b64 in
                        TaskImageChip(index: idx + 1, base64: b64)
                    }

                    if !(item.block.task?.notes.isEmpty ?? true) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }

                    Text(item.isInbox ? "Inbox" : item.documentTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.05)))

                    if item.block.task?.reminderDate != nil {
                        Image(systemName: "alarm")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if item.block.task?.repeatRule != nil {
                        Image(systemName: "repeat")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .draggable("task:\(item.block.id)") {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.square")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(item.block.content.isEmpty ? "Task" : String(item.block.content.prefix(36)))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
        .padding(.vertical, 2)
        .macDownsyncTaskShimmer(
            isHighlighted: isDownsynced,
            triggerId: downsyncWaveCoordinator?.shimmerTriggerId ?? UUID(),
            isDarkMode: colorScheme == .dark
        )
        .opacity(flightCoordinator?.shouldHideRow(item.block.id) == true ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("macWindowSpace"))
        } action: { frame in
            flightCoordinator?.reportRowFrame(frame, for: item.block.id)
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, raw.hasPrefix("task:") else { return false }
            let sourceId = String(raw.dropFirst("task:".count))
            HapticsManager.shared.boundarySnap()
            withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                store.reorderOrRescheduleTask(sourceBlockId: sourceId, targetBlockId: item.block.id, targetDay: day)
            }
            dropTargetedTaskId = nil
            return true
        } isTargeted: { targeted in
            if targeted && dropTargetedTaskId != item.block.id {
                HapticsManager.shared.tap()
            }
            withAnimation(CraftTheme.hoverEase(reduceMotion: reduceMotion)) {
                dropTargetedTaskId = targeted ? item.block.id : (dropTargetedTaskId == item.block.id ? nil : dropTargetedTaskId)
            }
        }
    }

    private func handleTaskStateChange(item: ResolvedTaskItem, newState: TaskCompletionState, day: Date) {
        let id = item.block.id
        lingerTimers[id]?.cancel()
        lingerTimers.removeValue(forKey: id)

        if newState == .pending {
            lingeringTaskIds.remove(id)
            showTodayCelebration = false
            store.setTaskState(docId: item.documentId, blockId: id, state: newState)
            return
        }

        // Stay visible for 3s so double-click cross-out or quick undo never races with removal.
        lingeringTaskIds.insert(id)
        store.setTaskState(docId: item.documentId, blockId: id, state: newState)

        lingerTimers[id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            _ = withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                lingeringTaskIds.remove(id)
            }
            lingerTimers.removeValue(forKey: id)
            checkTodayCelebration(for: day)
        }
    }

    private func checkTodayCelebration(for day: Date) {
        guard calendar.isDateInToday(day) else { return }
        let todayTasks = store.allTasks().filter { item in
            guard let sched = item.block.task?.scheduleDate else { return false }
            return calendar.isDate(sched, inSameDayAs: day)
        }
        let remaining = todayTasks.filter { ($0.block.task?.state ?? .pending) == .pending || lingeringTaskIds.contains($0.block.id) }
        if !todayTasks.isEmpty && remaining.isEmpty {
            HapticsManager.shared.taskComplete()
            SoundManager.shared.playComplete()
            celebrationBurstProgress = 0
            withAnimation(CraftTheme.craftSpring(reduceMotion: reduceMotion)) {
                showTodayCelebration = true
            }
            withAnimation(.easeOut(duration: 0.75)) {
                celebrationBurstProgress = 1.0
            }
        }
    }

    private func dayNumberTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    private func weekdayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    private func relativeDayLabel(_ date: Date) -> String? {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return nil
    }
}
