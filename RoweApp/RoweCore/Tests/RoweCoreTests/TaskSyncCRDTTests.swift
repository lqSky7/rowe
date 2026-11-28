import Foundation
import Testing
@testable import RoweCore

@Suite("Task Sync CRDT & Ordering")
struct TaskSyncCRDTTests {
    private func makeTask(
        id: String,
        title: String,
        state: TaskCompletionState = .pending,
        scheduleDate: Date? = nil,
        updatedAt: Date,
        deletedAt: Date? = nil,
        sortOrder: Double? = nil
    ) -> Block {
        Block(
            id: id,
            documentId: "rowe-seed-inbox",
            content: title,
            listStyle: .todo,
            task: TaskMetadata(state: state, scheduleDate: scheduleDate, isInbox: true),
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortOrder: sortOrder
        )
    }

    @Test("Backward-compatible JSON decoding for legacy blocks without deletedAt or sortOrder")
    func testLegacyBlockDecoding() throws {
        let legacyJSON = """
        {
          "id": "legacy-1",
          "documentId": "rowe-seed-inbox",
          "kind": "text",
          "content": "Legacy task",
          "listStyle": "todo",
          "updatedAt": 1730000000
        }
        """
        let block = try JSONDecoder().decode(Block.self, from: Data(legacyJSON.utf8))
        #expect(block.id == "legacy-1")
        #expect(block.deletedAt == nil)
        #expect(block.sortOrder == nil)
        #expect(block.isTask == true)
        #expect(block.isTaskOrTombstone == true)

        var tombstoned = block
        tombstoned.deletedAt = Date()
        #expect(tombstoned.isTask == false)
        #expect(tombstoned.isTaskOrTombstone == true)
    }

    @Test("CRDT merge is commutative, associative, and idempotent with identical cross-device order")
    @MainActor
    func testCRDTMergeAlgebraicProperties() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let t1 = makeTask(id: "t-1", title: "Alpha", updatedAt: base, sortOrder: 100)
        let t2 = makeTask(id: "t-2", title: "Beta", updatedAt: base.addingTimeInterval(1), sortOrder: 200)
        let t3 = makeTask(id: "t-3", title: "Gamma", updatedAt: base.addingTimeInterval(2), sortOrder: 300)
        let t2Done = makeTask(id: "t-2", title: "Beta", state: .completed, updatedAt: base.addingTimeInterval(5), sortOrder: 200)

        let deviceA = [t3, t1, t2]
        let deviceB = [t2Done, t1]
        let deviceC = [t3, makeTask(id: "t-4", title: "Delta", updatedAt: base.addingTimeInterval(3), sortOrder: 150)]

        // Commutativity: merge(A, B) == merge(B, A)
        let ab = WorkspaceStore.mergeTaskBlocksCRDT(local: deviceA, remote: deviceB, documentId: "inbox", now: base)
        let ba = WorkspaceStore.mergeTaskBlocksCRDT(local: deviceB, remote: deviceA, documentId: "inbox", now: base)
        #expect(ab == ba)
        #expect(ab.map(\.id) == ["t-1", "t-2", "t-3"])
        #expect(ab.first(where: { $0.id == "t-2" })?.task?.state == .completed)

        // Associativity: merge(merge(A, B), C) == merge(A, merge(B, C))
        let ab_c = WorkspaceStore.mergeTaskBlocksCRDT(local: ab, remote: deviceC, documentId: "inbox", now: base)
        let bc = WorkspaceStore.mergeTaskBlocksCRDT(local: deviceB, remote: deviceC, documentId: "inbox", now: base)
        let a_bc = WorkspaceStore.mergeTaskBlocksCRDT(local: deviceA, remote: bc, documentId: "inbox", now: base)
        #expect(ab_c == a_bc)
        #expect(ab_c.map(\.id) == ["t-1", "t-4", "t-2", "t-3"])

        // Idempotence: merge(X, X) == X
        let idem = WorkspaceStore.mergeTaskBlocksCRDT(local: ab_c, remote: ab_c, documentId: "inbox", now: base)
        #expect(idem == ab_c)
    }

    @Test("Concurrent offline creations on macOS and iOS both survive in identical order without duplicates")
    @MainActor
    func testConcurrentOfflineAdditions() {
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        let shared = makeTask(id: "shared-1", title: "Shared task", updatedAt: t0, sortOrder: 100)
        let macTask = makeTask(id: "mac-1", title: "Created on Mac", updatedAt: t0.addingTimeInterval(10), sortOrder: 110)
        let iosTask = makeTask(id: "ios-1", title: "Created on iOS", updatedAt: t0.addingTimeInterval(12), sortOrder: 112)

        let macView = WorkspaceStore.mergeTaskBlocksCRDT(local: [shared, macTask], remote: [shared, iosTask], documentId: "inbox", now: t0)
        let iosView = WorkspaceStore.mergeTaskBlocksCRDT(local: [shared, iosTask], remote: [shared, macTask], documentId: "inbox", now: t0)

        #expect(macView.map(\.id) == ["shared-1", "mac-1", "ios-1"])
        #expect(macView == iosView)
    }

    @Test("Offline delete tombstone propagates and never resurrects; 30-day GC drops expired tombstones")
    @MainActor
    func testTombstonePropagationAndGC() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let alive = makeTask(id: "del-1", title: "To delete", updatedAt: now.addingTimeInterval(-60), sortOrder: 10)
        let deleted = makeTask(
            id: "del-1",
            title: "To delete",
            updatedAt: now.addingTimeInterval(-10),
            deletedAt: now.addingTimeInterval(-10),
            sortOrder: 10
        )
        let ancientTombstone = makeTask(
            id: "old-del",
            title: "Ancient",
            updatedAt: now.addingTimeInterval(-35 * 86400),
            deletedAt: now.addingTimeInterval(-35 * 86400),
            sortOrder: 5
        )

        let merged = WorkspaceStore.mergeTaskBlocksCRDT(local: [alive, ancientTombstone], remote: [deleted], documentId: "inbox", now: now)
        // Recent tombstone survives (hidden from isTask) so offline devices receive the delete
        let delBlock = merged.first(where: { $0.id == "del-1" })
        #expect(delBlock != nil)
        #expect(delBlock?.deletedAt != nil)
        #expect(delBlock?.isTask == false)
        // Ancient (>30d) tombstone is garbage-collected
        #expect(merged.first(where: { $0.id == "old-del" }) == nil)
    }

    @Test("Equal-timestamp tie-breaker is deterministic across both devices")
    @MainActor
    func testDeterministicEqualTimestampTieBreaker() {
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        let pending = makeTask(id: "tie-1", title: "Task", state: .pending, updatedAt: t, sortOrder: 100)
        let completed = makeTask(id: "tie-1", title: "Task", state: .completed, updatedAt: t, sortOrder: 100)
        let deleted = makeTask(id: "tie-1", title: "Task", state: .pending, updatedAt: t, deletedAt: t, sortOrder: 100)

        // Completed beats pending deterministically in both directions
        let ab = WorkspaceStore.mergeTaskBlocksCRDT(local: [pending], remote: [completed], documentId: "inbox", now: t)
        let ba = WorkspaceStore.mergeTaskBlocksCRDT(local: [completed], remote: [pending], documentId: "inbox", now: t)
        #expect(ab == ba)
        #expect(ab.first?.task?.state == .completed)

        // Tombstone beats active deterministically in both directions
        let td1 = WorkspaceStore.mergeTaskBlocksCRDT(local: [completed], remote: [deleted], documentId: "inbox", now: t)
        let td2 = WorkspaceStore.mergeTaskBlocksCRDT(local: [deleted], remote: [completed], documentId: "inbox", now: t)
        #expect(td1 == td2)
        #expect(td1.first?.deletedAt != nil)
    }

    @Test("Fractional drag-reorder syncs exact task order to another device")
    @MainActor
    func testFractionalReorderSyncsAcrossDevices() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rowe-test-\(UUID().uuidString)")
        let store = WorkspaceStore(directoryURL: tempDir)
        let today = Calendar.current.startOfDay(for: Date())

        // Clear seed inbox tasks for clean deterministic assertion
        if let inboxIdx = store.documents.firstIndex(where: { $0.title == "Tasks Inbox" }) {
            store.documents[inboxIdx].blocks = []
        }

        let a = store.addInboxTask(title: "First", scheduleDate: today)
        let b = store.addInboxTask(title: "Second", scheduleDate: today)
        let c = store.addInboxTask(title: "Third", scheduleDate: today)

        let initialInbox = store.documents.first(where: { $0.title == "Tasks Inbox" })!.blocks
        #expect(store.allTasks().filter { $0.documentId == a.documentId }.map(\.block.id) == [a.block.id, b.block.id, c.block.id])

        // Reorder C before B -> expected order [A, C, B]
        store.reorderOrRescheduleTask(sourceBlockId: c.block.id, targetBlockId: b.block.id, targetDay: today)
        let reorderedIds = store.allTasks().filter { $0.documentId == a.documentId }.map(\.block.id)
        #expect(reorderedIds == [a.block.id, c.block.id, b.block.id])

        // Simulate syncing reordered inbox to a second device that still has initialInbox
        let updatedInbox = store.documents.first(where: { $0.title == "Tasks Inbox" })!.blocks
        let peerMerged = WorkspaceStore.mergeTaskBlocksCRDT(local: initialInbox, remote: updatedInbox, documentId: a.documentId)
        #expect(peerMerged.filter(\.isTask).map(\.id) == [a.block.id, c.block.id, b.block.id])
    }

    @Test("Ticking a legacy task without sortOrder freezes its position")
    @MainActor
    func testTickingLegacyTaskPreservesOrder() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rowe-test-\(UUID().uuidString)")
        let store = WorkspaceStore(directoryURL: tempDir)
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)

        let docId = store.documents.first(where: { $0.title == "Tasks Inbox" })!.id
        let legacy1 = makeTask(id: "leg-1", title: "First", updatedAt: t0, sortOrder: nil)
        let legacy2 = makeTask(id: "leg-2", title: "Second", updatedAt: t0.addingTimeInterval(60), sortOrder: nil)
        if let idx = store.documents.firstIndex(where: { $0.id == docId }) {
            store.documents[idx].blocks = [legacy1, legacy2]
        }

        // Tick legacy1 (its updatedAt becomes Date() >> legacy2.updatedAt, but sortOrder must freeze at t0)
        store.setTaskState(docId: docId, blockId: "leg-1", state: .completed)
        let ordered = store.allTasks().filter { $0.documentId == docId }.map(\.block.id)
        #expect(ordered == ["leg-1", "leg-2"])
    }

    @Test("Downsync task delta fires ONLY for task add/update/reorder/delete, never for non-task edits")
    @MainActor
    func testTaskOnlyDownsyncDelta() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let t1 = makeTask(id: "t1", title: "Buy milk", updatedAt: now, sortOrder: 100)
        let note = Block(id: "n1", documentId: "doc-1", content: "Regular paragraph", updatedAt: now)
        let noteEdited = Block(id: "n1", documentId: "doc-1", content: "Edited paragraph", updatedAt: now.addingTimeInterval(5))

        // 1. Non-task edit -> empty delta (no downsync wave)
        let nonTaskDelta = WorkspaceStore.computeTaskSyncDelta(before: [t1, note], after: [t1, noteEdited])
        #expect(nonTaskDelta.addedOrUpdated.isEmpty)
        #expect(nonTaskDelta.deleted.isEmpty)

        // 2. Task added
        let t2 = makeTask(id: "t2", title: "New task", updatedAt: now, sortOrder: 200)
        let addDelta = WorkspaceStore.computeTaskSyncDelta(before: [t1], after: [t1, t2])
        #expect(addDelta.addedOrUpdated == ["t2"])
        #expect(addDelta.deleted.isEmpty)

        // 3. Task reordered (sortOrder changed)
        let t1Reordered = makeTask(id: "t1", title: "Buy milk", updatedAt: now.addingTimeInterval(2), sortOrder: 300)
        let reorderDelta = WorkspaceStore.computeTaskSyncDelta(before: [t1], after: [t1Reordered])
        #expect(reorderDelta.addedOrUpdated == ["t1"])

        // 4. Task deleted (tombstoned)
        let t1Deleted = makeTask(id: "t1", title: "Buy milk", updatedAt: now.addingTimeInterval(3), deletedAt: now.addingTimeInterval(3), sortOrder: 100)
        let deleteDelta = WorkspaceStore.computeTaskSyncDelta(before: [t1], after: [t1Deleted])
        #expect(deleteDelta.addedOrUpdated.isEmpty)
        #expect(deleteDelta.deleted == ["t1"])
    }

    @Test("RoweDatabaseActor preserves fractional-second ISO8601 timestamps and sortOrder")
    func testFractionalISO8601DatabaseRoundTrip() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rowe-db-\(UUID().uuidString)")
        let db = RoweDatabaseActor(directoryURL: tempDir)
        let preciseDate = Date(timeIntervalSince1970: 1_750_000_123.456)
        let block = Block(
            id: "precise-1",
            documentId: "doc-1",
            content: "Sub-second task",
            listStyle: .todo,
            task: TaskMetadata(state: .pending, isInbox: true),
            updatedAt: preciseDate,
            deletedAt: nil,
            sortOrder: 1234.5678
        )
        let seed = SeedDataFactory.makeInitialWorkspace()
        let doc = RoweDocument(id: "doc-1", spaceId: seed.space.id, title: "Tasks Inbox", blocks: [block], updatedAt: preciseDate)
        let snap = WorkspaceSnapshot(
            space: seed.space,
            folders: seed.folders,
            tags: seed.tags,
            sidebarSections: seed.sidebarSections,
            documents: [doc],
            sharedDocuments: [],
            connections: [],
            settings: seed.settings
        )
        await db.flushNow(snap)
        let loaded = await db.load()
        let loadedBlock = loaded?.documents.first?.blocks.first
        #expect(loadedBlock?.id == "precise-1")
        #expect(loadedBlock?.sortOrder == 1234.5678)
        let diff = abs((loadedBlock?.updatedAt.timeIntervalSince1970 ?? 0) - preciseDate.timeIntervalSince1970)
        #expect(diff < 0.002)
    }
}
