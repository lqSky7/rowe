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

    private var activeActivity: Activity<RoweSyncActivityAttributes>?
    private var dismissTask: Task<Void, Never>?
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
                spaceName: store.space.name,
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
        dismissTask?.cancel()
        dismissTask = nil

        let state = RoweSyncActivityAttributes.ContentState(
            phase: phase,
            taskTitle: taskTitle,
            pendingCount: pendingCount,
            updatedAt: Date()
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))

        if let existing = activeActivity ?? Activity<RoweSyncActivityAttributes>.activities.first {
            activeActivity = existing
            Task { await existing.update(content) }
        } else {
            let attrs = RoweSyncActivityAttributes(spaceName: spaceName)
            if let created = try? Activity.request(attributes: attrs, content: content, pushType: nil) {
                activeActivity = created
            }
        }
    }

    private func finishActivity(
        spaceName: String,
        phase: RoweSyncActivityAttributes.SyncPhase,
        taskTitle: String
    ) {
        guard let activity = activeActivity ?? Activity<RoweSyncActivityAttributes>.activities.first else { return }
        let finalState = RoweSyncActivityAttributes.ContentState(
            phase: phase,
            taskTitle: taskTitle,
            pendingCount: 0,
            updatedAt: Date()
        )
        let content = ActivityContent(state: finalState, staleDate: nil)
        Task {
            await activity.update(content)
            let dismissalDelay: TimeInterval = (phase == .synced) ? 2.5 : 3.5
            await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(dismissalDelay)))
            await MainActor.run {
                if self.activeActivity?.id == activity.id {
                    self.activeActivity = nil
                }
            }
        }
    }
}
