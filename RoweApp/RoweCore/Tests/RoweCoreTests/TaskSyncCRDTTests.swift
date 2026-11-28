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
            documentId: "tasks-day-2026-11-28",
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
        let ab = WorkspaceStore.mergeTaskBlocksCRDT(local: deviceA, remote: deviceB, documentId: "tasks-day-2026-11-28", now: base)
        let ba = WorkspaceStore.mergeTaskBlocksCRDT(local: deviceB, remote: deviceA, documentId: "tasks-day-2026-11-28", now: base)
        #expect(ab == ba)
        #expect(ab.map(\.id) == ["t-1", "t-2", "t-3"])
        #expect(ab.first(where: { $0.id == "t-2" })?.task?.state == .completed)

        // Associativity: merge(merge(A, B), C) == merge(A, merge(B, C))
        let ab_c = WorkspaceStore.mergeTaskBlocksCRDT(local: ab, remote: deviceC, documentId: "tasks-day-2026-11-28", now: base)
        let bc = WorkspaceStore.mergeTaskBlocksCRDT(local: deviceB, remote: deviceC, documentId: "tasks-day-2026-11-28", now: base)
        let a_bc = WorkspaceStore.mergeTaskBlocksCRDT(local: deviceA, remote: bc, documentId: "tasks-day-2026-11-28", now: base)
        #expect(ab_c == a_bc)
        #expect(ab_c.map(\.id) == ["t-1", "t-4", "t-2", "t-3"])

        // Idempotence: merge(X, X) == X
        let idem = WorkspaceStore.mergeTaskBlocksCRDT(local: ab_c, remote: ab_c, documentId: "tasks-day-2026-11-28", now: base)
        #expect(idem == ab_c)
    }

    @Test("Concurrent offline creations on macOS and iOS both survive in identical order without duplicates")
    @MainActor
    func testConcurrentOfflineAdditions() {
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        let shared = makeTask(id: "shared-1", title: "Shared task", updatedAt: t0, sortOrder: 100)
        let macTask = makeTask(id: "mac-1", title: "Created on Mac", updatedAt: t0.addingTimeInterval(10), sortOrder: 110)
        let iosTask = makeTask(id: "ios-1", title: "Created on iOS", updatedAt: t0.addingTimeInterval(12), sortOrder: 112)

        let macView = WorkspaceStore.mergeTaskBlocksCRDT(local: [shared, macTask], remote: [shared, iosTask], documentId: "tasks-day-2026-11-28", now: t0)
        let iosView = WorkspaceStore.mergeTaskBlocksCRDT(local: [shared, iosTask], remote: [shared, macTask], documentId: "tasks-day-2026-11-28", now: t0)

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

        let merged = WorkspaceStore.mergeTaskBlocksCRDT(local: [alive, ancientTombstone], remote: [deleted], documentId: "tasks-day-2026-11-28", now: now)
        let delBlock = merged.first(where: { $0.id == "del-1" })
        #expect(delBlock != nil)
        #expect(delBlock?.deletedAt != nil)
        #expect(delBlock?.isTask == false)
        #expect(merged.first(where: { $0.id == "old-del" }) == nil)
    }

    @Test("Equal-timestamp tie-breaker is deterministic across both devices")
    @MainActor
    func testDeterministicEqualTimestampTieBreaker() {
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        let pending = makeTask(id: "tie-1", title: "Task", state: .pending, updatedAt: t, sortOrder: 100)
        let completed = makeTask(id: "tie-1", title: "Task", state: .completed, updatedAt: t, sortOrder: 100)
        let deleted = makeTask(id: "tie-1", title: "Task", state: .pending, updatedAt: t, deletedAt: t, sortOrder: 100)

        let ab = WorkspaceStore.mergeTaskBlocksCRDT(local: [pending], remote: [completed], documentId: "tasks-day-2026-11-28", now: t)
        let ba = WorkspaceStore.mergeTaskBlocksCRDT(local: [completed], remote: [pending], documentId: "tasks-day-2026-11-28", now: t)
        #expect(ab == ba)
        #expect(ab.first?.task?.state == .completed)

        let td1 = WorkspaceStore.mergeTaskBlocksCRDT(local: [completed], remote: [deleted], documentId: "tasks-day-2026-11-28", now: t)
        let td2 = WorkspaceStore.mergeTaskBlocksCRDT(local: [deleted], remote: [completed], documentId: "tasks-day-2026-11-28", now: t)
        #expect(td1 == td2)
        #expect(td1.first?.deletedAt != nil)
    }

    @Test("Fractional drag-reorder syncs exact task order to another device")
    @MainActor
    func testFractionalReorderSyncsAcrossDevices() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rowe-test-\(UUID().uuidString)")
        let store = WorkspaceStore(directoryURL: tempDir)
        let today = Calendar.current.startOfDay(for: Date())
        let dayDocId = WorkspaceStore.taskDayDocumentId(for: today)

        let a = store.addInboxTask(title: "First", scheduleDate: today)
        let b = store.addInboxTask(title: "Second", scheduleDate: today)
        let c = store.addInboxTask(title: "Third", scheduleDate: today)

        #expect(a.documentId == dayDocId)
        #expect(b.documentId == dayDocId)
        #expect(c.documentId == dayDocId)

        let initialDayBlocks = store.documents.first(where: { $0.id == dayDocId })!.blocks
        #expect(store.allTasks().filter { $0.documentId == dayDocId }.map(\.block.id) == [a.block.id, b.block.id, c.block.id])

        // Reorder C before B -> expected order [A, C, B]
        store.reorderOrRescheduleTask(sourceBlockId: c.block.id, targetBlockId: b.block.id, targetDay: today)
        let reorderedIds = store.allTasks().filter { $0.documentId == dayDocId }.map(\.block.id)
        #expect(reorderedIds == [a.block.id, c.block.id, b.block.id])

        // Simulate syncing reordered day doc to a second device that still has initialDayBlocks
        let updatedDayBlocks = store.documents.first(where: { $0.id == dayDocId })!.blocks
        let peerMerged = WorkspaceStore.mergeTaskBlocksCRDT(local: initialDayBlocks, remote: updatedDayBlocks, documentId: dayDocId)
        #expect(peerMerged.filter(\.isTask).map(\.id) == [a.block.id, c.block.id, b.block.id])
    }

    @Test("Every day's tasks live in a separate deterministic hidden doc excluded from visibleDocuments")
    @MainActor
    func testPerDayHiddenTaskDocumentsAndVisibility() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rowe-test-\(UUID().uuidString)")
        let store = WorkspaceStore(directoryURL: tempDir)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        let t1 = store.addInboxTask(title: "Today task", scheduleDate: today)
        let t2 = store.addInboxTask(title: "Tomorrow task", scheduleDate: tomorrow)

        let todayDocId = WorkspaceStore.taskDayDocumentId(for: today)
        let tomorrowDocId = WorkspaceStore.taskDayDocumentId(for: tomorrow)
        #expect(todayDocId != tomorrowDocId)
        #expect(t1.documentId == todayDocId)
        #expect(t2.documentId == tomorrowDocId)

        let todayDoc = store.documents.first(where: { $0.id == todayDocId })
        let tomorrowDoc = store.documents.first(where: { $0.id == tomorrowDocId })
        #expect(todayDoc?.isTaskDayDocument == true)
        #expect(todayDoc?.isHiddenTaskDocument == true)
        #expect(tomorrowDoc?.isTaskDayDocument == true)
        #expect(tomorrowDoc?.isHiddenTaskDocument == true)

        #expect(!store.visibleDocuments.contains(where: { $0.id == todayDocId }))
        #expect(!store.visibleDocuments.contains(where: { $0.id == tomorrowDocId }))
    }

    @Test("Rescheduling a task to another day moves it to the target day doc and tombstones the old day doc")
    @MainActor
    func testCrossDayRescheduleMovesAndTombstonesOldDay() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rowe-test-\(UUID().uuidString)")
        let store = WorkspaceStore(directoryURL: tempDir)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        let t1 = store.addInboxTask(title: "Move me", scheduleDate: today)
        let todayDocId = WorkspaceStore.taskDayDocumentId(for: today)
        let tomorrowDocId = WorkspaceStore.taskDayDocumentId(for: tomorrow)

        store.reorderOrRescheduleTask(sourceBlockId: t1.block.id, targetBlockId: nil, targetDay: tomorrow)

        let oldDayBlock = store.documents.first(where: { $0.id == todayDocId })?.blocks.first(where: { $0.id == t1.block.id })
        let newDayBlock = store.documents.first(where: { $0.id == tomorrowDocId })?.blocks.first(where: { $0.id == t1.block.id })

        #expect(oldDayBlock?.deletedAt != nil)
        #expect(oldDayBlock?.isTask == false)
        #expect(newDayBlock?.deletedAt == nil)
        #expect(newDayBlock?.isTask == true)
        #expect(store.allTasks().filter { $0.block.id == t1.block.id }.count == 1)
    }

    @Test("Graphite in Dark Mode requests dark checkmark foreground so ticks stay visible")
    func testAccentColorCheckmarkContrast() {
        #expect(AccentColorChoice.graphite.prefersDarkForeground(isDark: true) == true)
        #expect(AccentColorChoice.graphite.prefersDarkForeground(isDark: false) == false)
        #expect(AccentColorChoice.slateSky.prefersDarkForeground(isDark: false) == false)
    }

    @Test("SearchIndexActor hides per-day task doc records while keeping individual tasks searchable")
    func testSearchIndexHidesPerDayTaskDocs() async {
        let index = SearchIndexActor()
        let today = Calendar.current.startOfDay(for: Date())
        let docId = WorkspaceStore.taskDayDocumentId(for: today)
        let taskBlock = Block(
            id: "search-task-1",
            documentId: docId,
            content: "Buy espresso beans",
            listStyle: .todo,
            task: TaskMetadata(state: .pending, scheduleDate: today, isInbox: true)
        )
        let hiddenDoc = RoweDocument(
            id: docId,
            spaceId: "space-1",
            title: WorkspaceStore.taskDayDocumentTitle(for: today),
            blocks: [taskBlock],
            isTaskDayDocument: true,
            taskDayDateKey: WorkspaceStore.taskDayDateKey(for: today)
        )
        await index.rebuildFullIndex(documents: [hiddenDoc], folders: [], tags: [], connections: [], sharedDocuments: [])

        let docHits = await index.searchContextual(query: "Tasks", context: .allDocs, maxDepth: .everything, autoDeepen: true)
        #expect(!docHits.hits.contains(where: {
            if case .document(let id) = $0.kind { return id == docId }
            return false
        }))

        let taskHits = await index.searchContextual(query: "espresso", context: .calendar, maxDepth: .everything, autoDeepen: true)
        #expect(taskHits.hits.contains(where: {
            if case .task(_, let bid) = $0.kind { return bid == "search-task-1" }
            return false
        }))
    }

    @Test("Ticking a legacy task without sortOrder freezes its position")
    @MainActor
    func testTickingLegacyTaskPreservesOrder() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rowe-test-\(UUID().uuidString)")
        let store = WorkspaceStore(directoryURL: tempDir)
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)

        let dayDoc = store.ensureTaskDayDocument(for: t0)
        let docId = dayDoc.id
        let legacy1 = makeTask(id: "leg-1", title: "First", updatedAt: t0, sortOrder: nil)
        let legacy2 = makeTask(id: "leg-2", title: "Second", updatedAt: t0.addingTimeInterval(60), sortOrder: nil)
        if let idx = store.documents.firstIndex(where: { $0.id == docId }) {
            store.documents[idx].blocks = [legacy1, legacy2]
        }

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

        let nonTaskDelta = WorkspaceStore.computeTaskSyncDelta(before: [t1, note], after: [t1, noteEdited])
        #expect(nonTaskDelta.addedOrUpdated.isEmpty)
        #expect(nonTaskDelta.deleted.isEmpty)

        let t2 = makeTask(id: "t2", title: "New task", updatedAt: now, sortOrder: 200)
        let addDelta = WorkspaceStore.computeTaskSyncDelta(before: [t1], after: [t1, t2])
        #expect(addDelta.addedOrUpdated == ["t2"])
        #expect(addDelta.deleted.isEmpty)

        let t1Reordered = makeTask(id: "t1", title: "Buy milk", updatedAt: now.addingTimeInterval(2), sortOrder: 300)
        let reorderDelta = WorkspaceStore.computeTaskSyncDelta(before: [t1], after: [t1Reordered])
        #expect(reorderDelta.addedOrUpdated == ["t1"])

        let t1Deleted = makeTask(id: "t1", title: "Buy milk", updatedAt: now.addingTimeInterval(3), deletedAt: now.addingTimeInterval(3), sortOrder: 100)
        let deleteDelta = WorkspaceStore.computeTaskSyncDelta(before: [t1], after: [t1Deleted])
        #expect(deleteDelta.addedOrUpdated.isEmpty)
        #expect(deleteDelta.deleted == ["t1"])
    }

    @Test("RoweDatabaseActor preserves fractional-second ISO8601 timestamps, sortOrder, and hidden task day metadata")
    func testFractionalISO8601DatabaseRoundTrip() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rowe-db-\(UUID().uuidString)")
        let db = RoweDatabaseActor(directoryURL: tempDir)
        let preciseDate = Date(timeIntervalSince1970: 1_750_000_123.456)
        let docId = WorkspaceStore.taskDayDocumentId(for: preciseDate)
        let block = Block(
            id: "precise-1",
            documentId: docId,
            content: "Sub-second task",
            listStyle: .todo,
            task: TaskMetadata(state: .pending, isInbox: true),
            updatedAt: preciseDate,
            deletedAt: nil,
            sortOrder: 1234.5678
        )
        let seed = SeedDataFactory.makeInitialWorkspace()
        let doc = RoweDocument(
            id: docId,
            spaceId: seed.space.id,
            title: WorkspaceStore.taskDayDocumentTitle(for: preciseDate),
            blocks: [block],
            isTaskDayDocument: true,
            taskDayDateKey: WorkspaceStore.taskDayDateKey(for: preciseDate),
            updatedAt: preciseDate
        )
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
        let loadedDoc = loaded?.documents.first
        let loadedBlock = loadedDoc?.blocks.first
        #expect(loadedDoc?.isTaskDayDocument == true)
        #expect(loadedDoc?.isHiddenTaskDocument == true)
        #expect(loadedBlock?.id == "precise-1")
        #expect(loadedBlock?.sortOrder == 1234.5678)
        let diff = abs((loadedBlock?.updatedAt.timeIntervalSince1970 ?? 0) - preciseDate.timeIntervalSince1970)
        #expect(diff < 0.002)
    }
}
