import Foundation

public enum RepeatFrequency: String, Codable, CaseIterable, Sendable {
    case daily = "Daily"
    case weekdays = "Weekdays"
    case weekly = "Weekly"
    case biweekly = "Every 2 Weeks"
    case monthly = "Monthly"
    case yearly = "Yearly"
}

public struct RepeatRule: Codable, Hashable, Sendable {
    public var frequency: RepeatFrequency
    public var weekdayIndex: Int?
    public var startDate: Date?

    public init(frequency: RepeatFrequency, weekdayIndex: Int? = nil, startDate: Date? = nil) {
        self.frequency = frequency
        self.weekdayIndex = weekdayIndex
        self.startDate = startDate
    }

    public var displayLabel: String {
        switch frequency {
        case .weekly:
            if let weekday = weekdayIndex, (1...7).contains(weekday) {
                let symbols = Calendar.current.weekdaySymbols
                return "Weekly on \(symbols[weekday - 1])"
            }
            return "Weekly"
        default:
            return frequency.rawValue
        }
    }
}

public struct TaskMetadata: Codable, Hashable, Sendable {
    public var state: TaskCompletionState
    public var scheduleDate: Date?
    public var deadlineDate: Date?
    public var reminderDate: Date?
    public var repeatRule: RepeatRule?
    public var checkedDate: Date?
    public var notes: String
    public var isInbox: Bool
    public var attachedImagesBase64: [String]

    public init(
        state: TaskCompletionState = .pending,
        scheduleDate: Date? = nil,
        deadlineDate: Date? = nil,
        reminderDate: Date? = nil,
        repeatRule: RepeatRule? = nil,
        checkedDate: Date? = nil,
        notes: String = "",
        isInbox: Bool = false,
        attachedImagesBase64: [String] = []
    ) {
        self.state = state
        self.scheduleDate = scheduleDate
        self.deadlineDate = deadlineDate
        self.reminderDate = reminderDate
        self.repeatRule = repeatRule
        self.checkedDate = checkedDate
        self.notes = notes
        self.isInbox = isInbox
        self.attachedImagesBase64 = attachedImagesBase64
    }

    private enum CodingKeys: String, CodingKey {
        case state, scheduleDate, deadlineDate, reminderDate, repeatRule, checkedDate, notes, isInbox, attachedImagesBase64
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decodeIfPresent(TaskCompletionState.self, forKey: .state) ?? .pending
        scheduleDate = try c.decodeIfPresent(Date.self, forKey: .scheduleDate)
        deadlineDate = try c.decodeIfPresent(Date.self, forKey: .deadlineDate)
        reminderDate = try c.decodeIfPresent(Date.self, forKey: .reminderDate)
        repeatRule = try c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule)
        checkedDate = try c.decodeIfPresent(Date.self, forKey: .checkedDate)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isInbox = try c.decodeIfPresent(Bool.self, forKey: .isInbox) ?? false
        attachedImagesBase64 = try c.decodeIfPresent([String].self, forKey: .attachedImagesBase64) ?? []
    }

    /// Mirrors Craft's `realmSetTaskProperties`: fills `repeatRule.startDate` from `scheduleDate`
    /// and stamps `checkedDate` when transitioning out of pending.
    public mutating func applyStateTransition(to newState: TaskCompletionState, now: Date = Date()) {
        if var rule = repeatRule, rule.startDate == nil, let sched = scheduleDate {
            rule.startDate = sched
            repeatRule = rule
        }
        if !(state == .pending && newState == .pending) {
            checkedDate = (newState == .pending) ? nil : (checkedDate ?? now)
        }
        state = newState
    }
}

public struct ResolvedTaskItem: Identifiable, Hashable, Sendable {
    public var id: String { block.id }
    public var block: Block
    public var documentId: String
    public var documentTitle: String
    public var isInbox: Bool

    public init(block: Block, documentId: String, documentTitle: String, isInbox: Bool) {
        self.block = block
        self.documentId = documentId
        self.documentTitle = documentTitle
        self.isInbox = isInbox
    }
}

public enum TaskScopeFilter: String, Codable, CaseIterable, Sendable {
    case inbox = "Inbox"
    case active = "Active"
    case upcoming = "Upcoming"
    case logbook = "Logbook"
    case all = "All"
}
