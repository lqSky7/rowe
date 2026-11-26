import SwiftUI
import RoweCore

struct AllTasksView: View {
    @Bindable var store: WorkspaceStore
    @State private var scope: TaskScopeFilter = .active
    @State private var quickTaskText: String = ""
    @State private var editingTask: ResolvedTaskItem?
    @State private var lingeringTaskIds: Set<String> = []
    @State private var lingerTimers: [String: Task<Void, Never>] = [:]

    private var filteredTasks: [ResolvedTaskItem] {
        let all = store.allTasks()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch scope {
        case .inbox:
            return all.filter {
                $0.isInbox && (($0.block.task?.state ?? .pending) == .pending || lingeringTaskIds.contains($0.block.id))
            }
        case .active:
            return all.filter {
                ($0.block.task?.state ?? .pending) == .pending || lingeringTaskIds.contains($0.block.id)
            }
        case .upcoming:
            return all.filter {
                (($0.block.task?.state ?? .pending) == .pending || lingeringTaskIds.contains($0.block.id)) &&
                ($0.block.task?.scheduleDate.map { $0 >= today } ?? false)
            }
        case .logbook:
            return all.filter { ($0.block.task?.state ?? .pending) != .pending && !lingeringTaskIds.contains($0.block.id) }
        case .all:
            return all
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Tasks")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()

                    LiquidGlassSegmentedControl(
                        items: TaskScopeFilter.allCases,
                        selection: $scope,
                        height: 30,
                        title: \.rawValue
                    )
                    .frame(width: 340)
                }
                .padding(.leading, store.isLeftSidebarVisible ? 24 : 58)
                .padding(.trailing, 24)
                .padding(.top, 14)
                .padding(.bottom, 12)
                .animation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations), value: store.isLeftSidebarVisible)

                Button {
                    HapticsManager.shared.tap()
                    store.activeTaskEditor = .create(defaultDate: Calendar.current.startOfDay(for: Date()))
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.accentColor)
                        Text("Add Task… (⌘J)")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredTasks) { item in
                            let state = item.block.task?.state ?? .pending
                            HStack(spacing: 10) {
                                TaskCheckboxControl(state: state) { newState in
                                    handleTaskStateChange(item: item, newState: newState)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        AnimatedStrikethroughText(
                                            item.block.content,
                                            isStruck: state != .pending && store.settings.completedTaskStyle == .strikethrough,
                                            font: .system(size: 14),
                                            lineLimit: 1,
                                            reduceMotion: store.settings.reduceAnimations
                                        )
                                        ForEach(Array((item.block.task?.attachedImagesBase64 ?? []).enumerated()), id: \.offset) { idx, b64 in
                                            TaskImageChip(index: idx + 1, base64: b64)
                                        }
                                    }
                                    HStack(spacing: 8) {
                                        Text(item.isInbox ? "Inbox" : item.documentTitle)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(.secondary)
                                        if let sched = item.block.task?.scheduleDate {
                                            Text(sched.formatted(date: .abbreviated, time: .omitted))
                                                .font(.system(size: 11.5))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    HapticsManager.shared.tap()
                                    store.activeTaskEditor = .edit(item)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) {
                                Divider().opacity(0.25).padding(.horizontal, 24)
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private func handleTaskStateChange(item: ResolvedTaskItem, newState: TaskCompletionState) {
        let id = item.block.id
        lingerTimers[id]?.cancel()
        lingerTimers.removeValue(forKey: id)

        if newState == .pending {
            lingeringTaskIds.remove(id)
            store.setTaskState(docId: item.documentId, blockId: id, state: newState)
            return
        }

        lingeringTaskIds.insert(id)
        store.setTaskState(docId: item.documentId, blockId: id, state: newState)

        lingerTimers[id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            _ = withAnimation(CraftTheme.craftSpring(reduceMotion: store.settings.reduceAnimations)) {
                lingeringTaskIds.remove(id)
            }
            lingerTimers.removeValue(forKey: id)
        }
    }
}
