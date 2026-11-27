import ActivityKit
import Foundation
import RoweCore
import UIKit

/// Coordinates guaranteed iOS background task sync (`beginBackgroundTask`) and
/// ActivityKit Live Activity status so tasks created right before closing the app
/// always finish syncing to Mac with live Lock Screen & Dynamic Island feedback.
@MainActor
final class IOSLiveActivitySyncManager {
    static let shared = IOSLiveActivitySyncManager()

    private var activeActivityId: String?
    private var lastSyncedTaskTitle: String = "Calendar Tasks"

    private init() {}

    func syncTaskInBackground(store: WorkspaceStore, taskTitle: String) {
        guard store.isSignedIn else { return }
        lastSyncedTaskTitle = taskTitle
        startOrUpdateActivity(
            spaceName: store.space.name,
            phase: .syncing,
            taskTitle: taskTitle,
            pendingCount: 1
        )
        runProtectedBackgroundSync(store: store, taskTitle: taskTitle)
    }

    func flushPendingOnBackground(store: WorkspaceStore) {
        guard store.isSignedIn, store.hasPendingCloudSync else { return }
        startOrUpdateActivity(
            spaceName: store.space.name,
            phase: .syncing,
            taskTitle: lastSyncedTaskTitle,
            pendingCount: 1
        )
        runProtectedBackgroundSync(store: store, taskTitle: lastSyncedTaskTitle)
    }

    private func runProtectedBackgroundSync(store: WorkspaceStore, taskTitle: String) {
        var bgTaskId: UIBackgroundTaskIdentifier = .invalid
        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "RoweTaskSync") {
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
                bgTaskId = .invalid
            }
        }

        Task { @MainActor in
            await store.syncWithBackend()
            let succeeded = !store.hasPendingCloudSync
            self.finishActivity(
                phase: succeeded ? .synced : .offline,
                taskTitle: taskTitle
            )
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
                bgTaskId = .invalid
            }
        }
    }

    private func startOrUpdateActivity(
        spaceName: String,
        phase: RoweSyncActivityAttributes.SyncPhase,
        taskTitle: String,
        pendingCount: Int
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = RoweSyncActivityAttributes.ContentState(
            phase: phase,
            taskTitle: taskTitle,
            pendingCount: pendingCount,
            updatedAt: Date()
        )
        let staleDate = Date().addingTimeInterval(60)

        if let existingId = activeActivityId ?? Activity<RoweSyncActivityAttributes>.activities.first?.id {
            activeActivityId = existingId
            Task.detached {
                await Self.updateActivity(id: existingId, state: state, staleDate: staleDate)
            }
        } else {
            let attrs = RoweSyncActivityAttributes(spaceName: spaceName)
            let content = ActivityContent(state: state, staleDate: staleDate)
            if let created = try? Activity.request(attributes: attrs, content: content, pushType: nil) {
                activeActivityId = created.id
            }
        }
    }

    private func finishActivity(
        phase: RoweSyncActivityAttributes.SyncPhase,
        taskTitle: String
    ) {
        guard let targetId = activeActivityId ?? Activity<RoweSyncActivityAttributes>.activities.first?.id else { return }
        let finalState = RoweSyncActivityAttributes.ContentState(
            phase: phase,
            taskTitle: taskTitle,
            pendingCount: 0,
            updatedAt: Date()
        )
        let dismissalDelay: TimeInterval = (phase == .synced) ? 2.5 : 3.5

        Task.detached {
            await Self.endActivity(id: targetId, finalState: finalState, dismissalDelay: dismissalDelay)
            await MainActor.run {
                if IOSLiveActivitySyncManager.shared.activeActivityId == targetId {
                    IOSLiveActivitySyncManager.shared.activeActivityId = nil
                }
            }
        }
    }

    private nonisolated static func updateActivity(
        id: String,
        state: RoweSyncActivityAttributes.ContentState,
        staleDate: Date?
    ) async {
        guard let activity = Activity<RoweSyncActivityAttributes>.activities.first(where: { $0.id == id }) else {
            return
        }
        let content = ActivityContent(state: state, staleDate: staleDate)
        await activity.update(content)
    }

    private nonisolated static func endActivity(
        id: String,
        finalState: RoweSyncActivityAttributes.ContentState,
        dismissalDelay: TimeInterval
    ) async {
        guard let activity = Activity<RoweSyncActivityAttributes>.activities.first(where: { $0.id == id }) else {
            return
        }
        let content = ActivityContent(state: finalState, staleDate: nil)
        await activity.update(content)
        await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(dismissalDelay)))
    }
}
