import Foundation

/// Captures blocks + editor selection/caret state so Cmd+Z / Shift+Cmd+Z restores focus accurately.
public struct EditorUndoSnapshot: Equatable, Sendable {
    public var blocks: [Block]
    public var activeBlockId: String?
    public var selectedBlockIds: Set<String>
    public var caretUTF16Offset: Int?

    public init(
        blocks: [Block],
        activeBlockId: String?,
        selectedBlockIds: Set<String>,
        caretUTF16Offset: Int? = nil
    ) {
        self.blocks = blocks
        self.activeBlockId = activeBlockId
        self.selectedBlockIds = selectedBlockIds
        self.caretUTF16Offset = caretUTF16Offset
    }
}

/// Snapshot-based undo/redo coordinator matching Craft's TimedUndoManager 1.0s typing coalesce window.
@MainActor
public final class UndoCoordinator<Snapshot: Equatable> {
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private let maxDepth: Int
    private var lastPushTime: Date = .distantPast

    public init(maxDepth: Int = 100) {
        self.maxDepth = maxDepth
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func record(before snapshot: Snapshot, coalesceWindow: TimeInterval = 1.0) {
        let now = Date()
        if let last = undoStack.last {
            if last == snapshot { return }
            if coalesceWindow > 0 && now.timeIntervalSince(lastPushTime) < coalesceWindow {
                lastPushTime = now
                redoStack.removeAll()
                return
            }
        }
        undoStack.append(snapshot)
        if undoStack.count > maxDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        lastPushTime = now
    }

    public func breakGrouping() {
        lastPushTime = .distantPast
    }

    public func undo(current: Snapshot) -> Snapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        lastPushTime = .distantPast
        return previous
    }

    public func redo(current: Snapshot) -> Snapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        lastPushTime = .distantPast
        return next
    }

    public func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
