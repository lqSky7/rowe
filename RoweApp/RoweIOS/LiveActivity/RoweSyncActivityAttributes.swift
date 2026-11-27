import ActivityKit
import Foundation

/// Shared Live Activity attributes compiled into both `RoweIOS` and `RoweWidgetExtension`
/// so task sync updates smoothly on Lock Screen & Dynamic Island even after closing the app.
public struct RoweSyncActivityAttributes: ActivityAttributes {
    public enum SyncPhase: String, Codable, Hashable, Sendable {
        case syncing
        case synced
        case offline
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public var phase: SyncPhase
        public var taskTitle: String
        public var pendingCount: Int
        public var updatedAt: Date

        public init(
            phase: SyncPhase,
            taskTitle: String,
            pendingCount: Int = 1,
            updatedAt: Date = Date()
        ) {
            self.phase = phase
            self.taskTitle = taskTitle
            self.pendingCount = pendingCount
            self.updatedAt = updatedAt
        }
    }

    public var spaceName: String

    public init(spaceName: String) {
        self.spaceName = spaceName
    }
}
