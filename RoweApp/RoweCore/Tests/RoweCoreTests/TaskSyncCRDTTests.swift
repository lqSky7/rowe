import Foundation
import XCTest
@testable import RoweCore

final class TaskSyncCRDTTests: XCTestCase {
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
        XCTAssertEqual(block.id, "legacy-1")
        XCTAssertNil(block.deletedAt)
        XCTAssertNil(block.sortOrder)
        XCTAssertTrue(block.isTask)
        XCTAssertTrue(block.isTaskOrTombstone)

        var tombstoned = block
        tombstoned.deletedAt = Date()
        XCTAssertFalse(tombstoned.isTask)
        XCTAssertTrue(tombstoned.isTaskOrTombstone)
    }

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
        XCTAssertEqual(ab, ba)
        XCTAssertEqual(ab.map(\.id), ["t-1", "t-2", "t-3"])
        XCTAssertEqual(ab.first(where: { $0.id == "t-2" })?.task?.state, .completed)

        // Associativity: merge(merge(A, B), C) == merge(A, merge(B, C))
        let ab_c = WorkspaceStore.mergeTaskBlocksCRDT(local: ab, remote: deviceC, documentId: "inbox", now: base)
        let bc = WorkspaceStore.mergeTaskBlocksCRDT(local: deviceB, remote: deviceC, documentId: "inbox", now: base)
        let a_bc = WorkspaceStore.mergeTaskBlocksCRDT(local: deviceA, remote: bc, documentId: "inbox", now: base)
        XCTAssertEqual(ab_c, a_bc)
        XCTAssertEqual(ab_c.map(\.id), ["t-1", "t-4", "t-2", "t-3"])

        // Idempotence: merge(X, X) == X
        let idem = WorkspaceStore.mergeTaskBlocksCRDT(local: ab_c, remote: ab_c, documentId: "inbox", now: base)
        XCTAssertEqual(idem, ab_c)
    }

    @MainActor
    func testConcurrentOfflineAdditions() {
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        let shared = makeTask(id: "shared-1", title: "Shared task", updatedAt: t0, sortOrder: 100)
        let macTask = makeTask(id: "mac-1", title: "Created on Mac", updatedAt: t0.addingTimeInterval(10), sortOrder: 110)
        let iosTask = makeTask(id: "ios-1", title: "Created on iOS", updatedAt: t0.addingTimeInterval(12), sortOrder: 112)

        let macView = WorkspaceStore.mergeTaskBlocksCRDT(local: [shared, macTask], remote: [shared, iosTask], documentId: "inbox", now: t0)
        let iosView = WorkspaceStore.mergeTaskBlocksCRDT(local: [shared, iosTask], remote: [shared, macTask], documentId: "inbox", now: t0)

        XCTAssertEqual(macView.map(\.id), ["shared-1", "mac-1", "ios-1"])
        XCTAssertEqual(macView, iosView)
    }

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
        let delBlock = merged.first(where: { $0.id == "del-1" })
        XCTAssertNotNil(delBlock)
        XCTAssertNotNil(delBlock?.deletedAt)
        XCTAssertEqual(delBlock?.isTask, false)
        XCTAssertNil(merged.first(where: { $0.id == "old-del" }))
    }

    @MainActor
    func testDeterministicEqualTimestampTieBreaker() {
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        let pending = makeTask(id: "tie-1", title: "Task", state: .pending, updatedAt: t, sortOrder: 100)
        let completed = makeTask(id: "tie-1", title: "Task", state: .completed, updatedAt: t, sortOrder: 100)
        let deleted = makeTask(id: "tie-1", title: "Task", state: .pending, updatedAt: t, deletedAt: t, sortOrder: 100)

        let ab = WorkspaceStore.mergeTaskBlocksCRDT(local: [pending], remote: [completed], documentId: "inbox", now: t)
        let ba = WorkspaceStore.mergeTaskBlocksCRDT(local: [completed], remote: [pending], documentId: "inbox", now: t)
        XCTAssertEqual(ab, ba)
        XCTAssertEqual(ab.first?.task?.state, .completed)

        let td1 = WorkspaceStore.mergeTaskBlocksCRDT(local: [completed], remote: [deleted], documentId: "inbox", now: t)
        let td2 = WorkspaceStore.mergeTaskBlocksCRDT(local: [deleted], remote: [completed], documentId: "inbox", now: t)
        XCTAssertEqual(td1, td2)
        XCTAssertNotNil(td1.first?.deletedAt)
    }

    @MainActor
    func testFractionalReorderSyncsAcrossDevices() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rowe-test-\(UUID().uuidString)")
        let store = WorkspaceStore(directoryURL: tempDir)
        let today = Calendar.current.startOfDay(for: Date())

        if let inboxIdx = store.documents.firstIndex(where: { $0.title == "Tasks Inbox" }) {
            store.documents[inboxIdx].blocks = []
        }

        let a = store.addInboxTask(title: "First", scheduleDate: today)
        let b = store.addInboxTask(title: "Second", scheduleDate: today)
        let c = store.addInboxTask(title: "Third", scheduleDate: today)

        let initialInbox = store.documents.first(where: { $0.title == "Tasks Inbox" })!.blocks
        XCTAssertEqual(store.allTasks().filter { $0.documentId == a.documentId }.map(\.block.id), [a.block.id, b.block.id, c.block.id])

        // Reorder C before B -> expected order [A, C, B]
        store.reorderOrRescheduleTask(sourceBlockId: c.block.id, targetBlockId: b.block.id, targetDay: today)
        let reorderedIds = store.allTasks().filter { $0.documentId == a.documentId }.map(\.block.id)
        XCTAssertEqual(reorderedIds, [a.block.id, c.block.id, b.block.id])

        // Simulate syncing reordered inbox to a second device that still has initialInbox
        let updatedInbox = store.documents.first(where: { $0.title == "Tasks Inbox" })!.blocks
        let peerMerged = WorkspaceStore.mergeTaskBlocksCRDT(local: initialInbox, remote: updatedInbox, documentId: a.documentId)
        XCTAssertEqual(peerMerged.filter(\.isTask).map(\.id), [a.block.id, c.block.id, b.block.id])
    }

    @MainActor
    func testTickingLegacyTaskPreservesOrder() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rowe-test-\(UUID().uuidString)")
        let store = WorkspaceStore(directoryURL: tempDir)
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)

        let inboxDoc = store.documents.first(where: { $0.title == "Tasks Inbox" })
            ?? store.createDocument(title: "Tasks Inbox", openImmediately: false)
        let docId = inboxDoc.id
        let legacy1 = makeTask(id: "leg-1", title: "First", updatedAt: t0, sortOrder: nil)
        let legacy2 = makeTask(id: "leg-2", title: "Second", updatedAt: t0.addingTimeInterval(60), sortOrder: nil)
        if let idx = store.documents.firstIndex(where: { $0.id == docId }) {
            store.documents[idx].blocks = [legacy1, legacy2]
        }

        store.setTaskState(docId: docId, blockId: "leg-1", state: .completed)
        let ordered = store.allTasks().filter { $0.documentId == docId }.map(\.block.id)
        XCTAssertEqual(ordered, ["leg-1", "leg-2"])
    }

    @MainActor
    func testTaskOnlyDownsyncDelta() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let t1 = makeTask(id: "t1", title: "Buy milk", updatedAt: now, sortOrder: 100)
        let note = Block(id: "n1", documentId: "doc-1", content: "Regular paragraph", updatedAt: now)
        let noteEdited = Block(id: "n1", documentId: "doc-1", content: "Edited paragraph", updatedAt: now.addingTimeInterval(5))

        // 1. Non-task edit -> empty delta (no downsync wave)
        let nonTaskDelta = WorkspaceStore.computeTaskSyncDelta(before: [t1, note], after: [t1, noteEdited])
        XCTAssertTrue(nonTaskDelta.addedOrUpdated.isEmpty)
        XCTAssertTrue(nonTaskDelta.deleted.isEmpty)

        // 2. Task added
        let t2 = makeTask(id: "t2", title: "New task", updatedAt: now, sortOrder: 200)
        let addDelta = WorkspaceStore.computeTaskSyncDelta(before: [t1], after: [t1, t2])
        XCTAssertEqual(addDelta.addedOrUpdated, ["t2"])
        XCTAssertTrue(addDelta.deleted.isEmpty)

        // 3. Task reordered (sortOrder changed)
        let t1Reordered = makeTask(id: "t1", title: "Buy milk", updatedAt: now.addingTimeInterval(2), sortOrder: 300)
        let reorderDelta = WorkspaceStore.computeTaskSyncDelta(before: [t1], after: [t1Reordered])
        XCTAssertEqual(reorderDelta.addedOrUpdated, ["t1"])

        // 4. Task deleted (tombstoned)
        let t1Deleted = makeTask(id: "t1", title: "Buy milk", updatedAt: now.addingTimeInterval(3), deletedAt: now.addingTimeInterval(3), sortOrder: 100)
        let deleteDelta = WorkspaceStore.computeTaskSyncDelta(before: [t1], after: [t1Deleted])
        XCTAssertTrue(deleteDelta.addedOrUpdated.isEmpty)
        XCTAssertEqual(deleteDelta.deleted, ["t1"])
    }

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
        XCTAssertEqual(loadedBlock?.id, "precise-1")
        XCTAssertEqual(loadedBlock?.sortOrder, 1234.5678)
        let diff = abs((loadedBlock?.updatedAt.timeIntervalSince1970 ?? 0) - preciseDate.timeIntervalSince1970)
        XCTAssertLessThan(diff, 0.002)
    }
}
