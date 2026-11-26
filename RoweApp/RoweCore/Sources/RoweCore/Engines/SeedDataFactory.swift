import Foundation

public enum SeedDataFactory {
    public static func makeInitialWorkspace(now: Date = Date()) -> WorkspaceSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let dayAfter = cal.date(byAdding: .day, value: 2, to: today) ?? today
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: now) ?? now
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: now) ?? now
        let oneMonthAgo = cal.date(byAdding: .day, value: -31, to: now) ?? now
        let twoMonthsAgo = cal.date(byAdding: .day, value: -62, to: now) ?? now

        let space = Space(name: "My Space", authorName: "Owner", createdAt: twoMonthsAgo)

        let unsortedFolder = Folder(spaceId: space.id, name: "Unsorted", iconName: "tray", sortOrder: 0)
        let researchFolder = Folder(spaceId: space.id, name: "AI Knowledge", iconName: "folder", sortOrder: 1)
        let booksFolder = Folder(spaceId: space.id, name: "Reading Notes", iconName: "books.vertical", sortOrder: 2)
        let swiftFolder = Folder(spaceId: space.id, name: "Swift", iconName: "swift", sortOrder: 3)
        let importedFolder = Folder(spaceId: space.id, name: "Imported Notes", iconName: "folder", sortOrder: 4)

        let trackerDocId = UUID().uuidString
        let colName = CollectionColumn(title: "Project", type: .text, width: 170)
        let colRegion = CollectionColumn(title: "Region", type: .singleSelect, width: 110)
        let colRole = CollectionColumn(title: "Stage", type: .singleSelect, width: 120)
        let colLink = CollectionColumn(title: "Link", type: .url, width: 170)
        let colNotes = CollectionColumn(title: "Focus", type: .text, width: 160)

        let collection = CollectionData(
            title: "Active Opportunities",
            viewMode: .table,
            columns: [colName, colRegion, colRole, colLink, colNotes],
            rows: [
                CollectionRow(values: [colName.id: "Northstar Labs", colRegion.id: "USA", colRole.id: "Active", colLink.id: "rowe.local/northstar", colNotes.id: "Systems Engineering"]),
                CollectionRow(values: [colName.id: "Maple Cloud", colRegion.id: "Canada", colRole.id: "Review", colLink.id: "rowe.local/maple", colNotes.id: "Distributed Storage"]),
                CollectionRow(values: [colName.id: "Solstice AI", colRegion.id: "Europe", colRole.id: "Active", colLink.id: "rowe.local/solstice", colNotes.id: "Inference Runtime"]),
                CollectionRow(values: [colName.id: "Indus Compute", colRegion.id: "India", colRole.id: "Active", colLink.id: "rowe.local/indus", colNotes.id: "Swift & Go Platform"]),
                CollectionRow(values: [colName.id: "Harbor Systems", colRegion.id: "USA", colRole.id: "Planned", colLink.id: "rowe.local/harbor", colNotes.id: "Core UI Engine"])
            ]
        )

        let trackerDoc = RoweDocument(
            id: trackerDocId,
            spaceId: space.id,
            folderId: nil,
            title: "Project Tracker",
            blocks: [
                Block(documentId: trackerDocId, kind: .objectList, content: "Active Opportunities", collectionData: collection)
            ],
            tags: ["planning"],
            isStarred: true,
            createdAt: twoMonthsAgo,
            updatedAt: twoWeeksAgo,
            lastViewedAt: oneWeekAgo
        )

        let scratchDocId = UUID().uuidString
        var formulaTable = TableData(rows: 4, columns: 3, hasHeaderRow: true, hasHeaderColumn: false)
        formulaTable.cells[0][0].rawContent = "Item"
        formulaTable.cells[0][1].rawContent = "Q1"
        formulaTable.cells[0][2].rawContent = "Q2"
        formulaTable.cells[1][0].rawContent = "Compute"
        formulaTable.cells[1][1].rawContent = "120"
        formulaTable.cells[1][2].rawContent = "145"
        formulaTable.cells[2][0].rawContent = "Storage"
        formulaTable.cells[2][1].rawContent = "40"
        formulaTable.cells[2][2].rawContent = "55"
        formulaTable.cells[3][0].rawContent = "Total"
        formulaTable.cells[3][1].rawContent = "=SUM(ABOVE)"
        formulaTable.cells[3][2].rawContent = "=SUM(ABOVE)"

        let scratchDoc = RoweDocument(
            id: scratchDocId,
            spaceId: space.id,
            folderId: swiftFolder.id,
            title: "Rowe Scratch — Document Behavior",
            blocks: [
                Block(documentId: scratchDocId, content: "Overview", textStyle: .subtitle),
                Block(documentId: scratchDocId, content: "Type / anywhere to open the Liquid Glass command palette. Single-click a task to complete it, or double-click instantly for a trackpad buzz to cross it out.", textStyle: .body),
                Block(documentId: scratchDocId, content: "Single-click completes a task with a crisp haptic tap", listStyle: .todo, task: TaskMetadata(state: .pending, scheduleDate: today, isInbox: false)),
                Block(documentId: scratchDocId, content: "Double-click instantly crosses out a task with buzz vibration", listStyle: .todo, task: TaskMetadata(state: .pending, scheduleDate: today, isInbox: false)),
                Block(documentId: scratchDocId, content: "Callout block using the Focus decoration style.", decoration: .focus),
                Block(documentId: scratchDocId, kind: .code, content: "actor RoweSync {\n    func debounceTier(ops: Int) -> Duration {\n        ops < 60 ? .milliseconds(140) : .seconds(ops < 80 ? 1 : 3)\n    }\n}", codeLanguage: "swift"),
                Block(documentId: scratchDocId, content: "Formula Table", textStyle: .heading),
                Block(documentId: scratchDocId, kind: .table, content: "Budget", tableData: formulaTable),
                Block(documentId: scratchDocId, kind: .line, content: "---"),
                Block(documentId: scratchDocId, content: "Toggle section with nested thoughts", listStyle: .toggle, subblocks: [
                    Block(documentId: scratchDocId, content: "Child block inside toggle", indentLevel: 1)
                ])
            ],
            tags: ["swift", "design"],
            createdAt: oneMonthAgo,
            updatedAt: oneMonthAgo,
            lastViewedAt: oneMonthAgo
        )

        let aiDocId = UUID().uuidString
        let aiDoc = RoweDocument(
            id: aiDocId,
            spaceId: space.id,
            folderId: researchFolder.id,
            title: "Attention Architecture Notes",
            blocks: [
                Block(documentId: aiDocId, content: "The Problem", textStyle: .subtitle),
                Block(documentId: aiDocId, content: "Sparse attention can reduce memory bandwidth while preserving recall. Inline math: $$\\text{Attn}(Q, K, V) = \\text{softmax}(QK^T / \\sqrt{d_k})V$$", textStyle: .body),
                Block(documentId: aiDocId, content: "Benchmark sparse KV-cache eviction latency", listStyle: .todo, task: TaskMetadata(state: .pending, scheduleDate: tomorrow))
            ],
            tags: ["ai"],
            createdAt: oneMonthAgo,
            updatedAt: oneMonthAgo,
            lastViewedAt: oneMonthAgo
        )

        let inboxDocId = UUID().uuidString
        let inboxDoc = RoweDocument(
            id: inboxDocId,
            spaceId: space.id,
            folderId: unsortedFolder.id,
            title: "Tasks Inbox",
            blocks: [
                Block(documentId: inboxDocId, content: "Review daily brief workflow in Rowe", listStyle: .todo, task: TaskMetadata(state: .pending, scheduleDate: today, isInbox: true)),
                Block(documentId: inboxDocId, content: "Test trackpad haptics on task completion and crossing", listStyle: .todo, task: TaskMetadata(state: .pending, scheduleDate: today, isInbox: true)),
                Block(documentId: inboxDocId, content: "Workout Session A — Upper Push", listStyle: .todo, task: TaskMetadata(state: .pending, scheduleDate: today, repeatRule: RepeatRule(frequency: .weekly, weekdayIndex: 4, startDate: today), notes: "Keep rest intervals steady", isInbox: true)),
                Block(documentId: inboxDocId, content: "Organize archived markdown notes", listStyle: .todo, task: TaskMetadata(state: .pending, scheduleDate: tomorrow, isInbox: true)),
                Block(documentId: inboxDocId, content: "Workout Session B — Pull & Core", listStyle: .todo, task: TaskMetadata(state: .pending, scheduleDate: dayAfter, repeatRule: RepeatRule(frequency: .weekly, weekdayIndex: 6, startDate: dayAfter), isInbox: true))
            ],
            createdAt: twoWeeksAgo,
            updatedAt: now,
            lastViewedAt: now
        )

        let sharedItems: [SharedDocumentItem] = [
            SharedDocumentItem(
                title: "Shared Feature Roadmap",
                preview: "--- ---",
                sharedByName: "Collaborator",
                sharedByInitial: "C",
                sharedByColorHex: "#8B3A1E",
                dateShared: oneMonthAgo,
                lastViewed: oneWeekAgo
            )
        ]

        let connections: [ConnectionItem] = [
            ConnectionItem(
                kind: .mcp,
                name: "MCP for All Documents",
                endpointURL: "http://localhost:8080/mcp/all-documents",
                documentScope: .allDocuments,
                permission: .readAndWrite,
                accessMode: .localOnly
            ),
            ConnectionItem(
                kind: .api,
                name: "API for Daily Notes & Tasks",
                endpointURL: "http://localhost:8080/api/v1/daily-tasks",
                documentScope: .dailyNotesAndTasks,
                permission: .readAndWrite,
                accessMode: .publicAccess
            )
        ]

        return WorkspaceSnapshot(
            space: space,
            folders: [unsortedFolder, researchFolder, booksFolder, swiftFolder, importedFolder],
            tags: [
                TagItem(name: "planning", isPinned: true, colorHex: "#2E7CF6"),
                TagItem(name: "swift", isPinned: true, colorHex: "#F97316"),
                TagItem(name: "ai", isPinned: false, colorHex: "#8B1D8E")
            ],
            sidebarSections: [
                SidebarSectionState(type: .starred, isVisible: true, isCollapsed: false),
                SidebarSectionState(type: .folders, isVisible: true, isCollapsed: false),
                SidebarSectionState(type: .tags, isVisible: true, isCollapsed: false)
            ],
            documents: [trackerDoc, scratchDoc, aiDoc, inboxDoc],
            sharedDocuments: sharedItems,
            connections: connections,
            settings: AppSettings()
        )
    }
}
