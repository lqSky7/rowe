import Foundation
import Observation

public enum PinPromptRequest: Identifiable, Hashable, Sendable {
    case setupPin(lockDocumentId: String?)
    case unlockDocument(docId: String)
    case changePin

    public var id: String {
        switch self {
        case .setupPin(let docId): return "setup-\(docId ?? "none")"
        case .unlockDocument(let docId): return "unlock-\(docId)"
        case .changePin: return "change-pin"
        }
    }
}

public enum TaskEditorRequest: Identifiable, Hashable, Sendable {
    case create(defaultDate: Date?)
    case edit(ResolvedTaskItem)

    public var id: String {
        switch self {
        case .create(let d): return "create-\(d?.timeIntervalSince1970 ?? 0)"
        case .edit(let item): return "edit-\(item.id)"
        }
    }
}

public enum WorkspaceDestination: Hashable, Sendable {
    case allDocs
    case tasks
    case calendar
    case connections
    case sharedWithMe
    case folder(String)
    case tag(String)
    case trash
    case document(String)
    case settings
}

public struct BrowserTab: Identifiable, Hashable, Sendable {
    public let id: String
    public var destination: WorkspaceDestination

    public init(id: String = UUID().uuidString, destination: WorkspaceDestination) {
        self.id = id
        self.destination = destination
    }
}

public enum AllDocsViewStyle: String, CaseIterable, Sendable {
    case gallery
    case grid
    case list
}

public enum AllDocsSortOrder: String, CaseIterable, Sendable {
    case updatedDesc = "Updated"
    case createdDesc = "Created"
    case lastViewedDesc = "Last Viewed"
    case titleAsc = "Name"
}

public enum SyncPulseDirection: String, Sendable {
    case sent
    case received
}

/// Mirrors Craft's v2BlockDetailsViewController_SelectionState.
public enum EditorSelectionMode: Equatable, Sendable {
    case noSelection
    case titleInlineSelection
    case inlineSelection
    case blockSelection
}

/// Imperative focus & caret placement directive consumed by RoweBlockTextView / Title.
public struct BlockCaretRequest: Equatable, Sendable {
    public let id: UUID
    public let blockId: String? // nil targets Page Title
    public let utf16Offset: Int?
    public let desiredX: Double?
    public let fromBottom: Bool
    public let selectAll: Bool

    public init(
        id: UUID = UUID(),
        blockId: String?,
        utf16Offset: Int? = nil,
        desiredX: Double? = nil,
        fromBottom: Bool = false,
        selectAll: Bool = false
    ) {
        self.id = id
        self.blockId = blockId
        self.utf16Offset = utf16Offset
        self.desiredX = desiredX
        self.fromBottom = fromBottom
        self.selectAll = selectAll
    }
}

/// Central @MainActor coordinator bridging SwiftUI views to background persistence,
/// search indexing, formula evaluation, export, and sync actors.
@MainActor
@Observable
public final class WorkspaceStore {
    public var space: Space
    public var folders: [Folder]
    public var tags: [TagItem]
    public var sidebarSections: [SidebarSectionState]
    public var documents: [RoweDocument]
    public var sharedDocuments: [SharedDocumentItem]
    public var connections: [ConnectionItem]
    public var settings: AppSettings

    public var tabs: [BrowserTab] = []
    public var activeTabId: String = ""
    public var navigationHistory: [WorkspaceDestination] = []
    public var navigationHistoryIndex: Int = -1

    public var isLeftSidebarVisible: Bool = true
    public var leftSidebarWidth: Double = 240.0
    public var isRightInspectorVisible: Bool = false
    public var isTabBarVisible: Bool = true
    public var isFocusMode: Bool = false
    public var isQuickOpenPresented: Bool = false
    public var isStyleGalleryPresented: Bool = false
    public var isLoginSheetPresented: Bool = false
    public var pinPromptRequest: PinPromptRequest?
    public var activeTaskEditor: TaskEditorRequest?
    public var selectedSettingsSectionId: String = "Appearance & Sound"

    // Auth & Coalesced Delta Cloud Sync
    public static let defaultServerURL = "https://rowe.traverses.dpdns.org"
    public var serverURL: String = WorkspaceStore.defaultServerURL
    public var authSession: AuthSession?
    public var authErrorMessage: String?
    public var isAuthBusy: Bool = false
    public var lastSyncStatusMessage: String?
    public var lastSuccessfulSyncAt: Date?
    public var syncPulseId: UUID = UUID()
    public var syncPulseDirection: SyncPulseDirection? = nil
    public var manualSyncWaveId: UUID = UUID()
    public var downsyncWaveId: UUID = UUID()
    public var downsyncedTaskIds: Set<String> = []
    public var hasLoadedFromDisk: Bool = false
    public var isSyncing: Bool = false
    public var isRealtimeSyncConnected: Bool = false
    public var hasPendingCloudSync: Bool { !dirtyDocumentIds.isEmpty }
    public var onTaskMutatedForLiveSync: ((String) -> Void)?
    private var dirtyDocumentIds: Set<String> = []
    private var dirtyDocumentVersions: [String: UInt64] = [:]
    private var pendingRemoteDeleteIds: Set<String> = []
    private var lastServerUpdatedAtByDoc: [String: Date] = [:]
    private var lastSyncServerTimeMs: Int64 = 0
    private var inFlightRefreshTask: Task<AuthSession, Error>? = nil
    private var syncDebounceTask: Task<Void, Never>?
    private var focusSyncDebounceTask: Task<Void, Never>?
    private var sseStreamTask: Task<Void, Never>?
    private var fallbackPollTask: Task<Void, Never>?
    private var needsFollowUpSync: Bool = false
    private var firstDirtyAt: Date?
    private var consecutiveSyncFailures: Int = 0

    // Adaptive Focus & Behavioral Nudge System (Zero Blocking, Cross-Device)
    public var focusBehavior: FocusBehaviorState = FocusBehaviorState()
    public var activeFocusSuggestion: FocusSuggestion? = nil
    public let deviceId: String = {
        let key = "rowe.stableDeviceId"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()
    private let focusEngine = FocusNudgeEngine()
    private let focusEstimator = FocusIntelligenceEstimator()

    // Zero-Knowledge PIN-Locked Notes (vaultKey & unlockedDocumentIds stay strictly in RAM)
    public var vaultEnvelope: VaultKeyEnvelope?
    public var unlockedDocumentIds: Set<String> = []
    public var failedPinAttempts: Int = 0
    public var pinLockoutUntil: Date?
    private var unlockedVaultKey: Data?

    public var editorSelectionMode: EditorSelectionMode = .noSelection
    public var selectedBlockIds: Set<String> = []
    public var selectionAnchorBlockId: String?
    public var activeBlockId: String?
    public var activeCaretUTF16Offset: Int?
    public var activeSelectionLength: Int = 0
    public var caretRequest: BlockCaretRequest?

    public var stats: WorkspaceStats = WorkspaceStats()
    public var syncDiagnostics: SyncDiagnostics = SyncDiagnostics()
    public var contextualSearchResponse: ContextualSearchResponse = ContextualSearchResponse()
    public var searchIndexStats: SearchIndexStats = SearchIndexStats()
    public var inDocumentMatches: [InDocumentMatch] = []
    public var evaluatedTables: [String: [[EvaluatedTableCell]]] = [:]

    private let database: RoweDatabaseActor
    private let searchIndex: SearchIndexActor
    private let syncScheduler: SyncSchedulerActor
    private let exportService: ExportServiceActor
    private let backendClient = RoweBackendClient()
    private let formulaEngine = FormulaEngine()
    private var docUndoStacks: [String: UndoCoordinator<EditorUndoSnapshot>] = [:]
    private var formulaTasks: [String: Task<Void, Never>] = [:]
    private var searchTask: Task<Void, Never>?
    private var inDocFindTask: Task<Void, Never>?
    private var lastSidebarToggleUptime: TimeInterval = 0

    public init(directoryURL: URL? = nil) {
        self.database = RoweDatabaseActor(directoryURL: directoryURL)
        self.searchIndex = SearchIndexActor()
        self.syncScheduler = SyncSchedulerActor()
        self.exportService = ExportServiceActor()

        let seed = SeedDataFactory.makeInitialWorkspace()
        self.space = seed.space
        self.folders = seed.folders
        self.tags = seed.tags
        self.sidebarSections = seed.sidebarSections
        self.documents = seed.documents
        self.sharedDocuments = seed.sharedDocuments
        self.connections = seed.connections
        var initialSettings = seed.settings
        if UserDefaults.standard.bool(forKey: "rowe.hasCompletedOnboarding") {
            initialSettings.hasCompletedOnboarding = true
        }
        self.settings = initialSettings

        let initialTab = BrowserTab(destination: .allDocs)
        self.tabs = [initialTab]
        self.activeTabId = initialTab.id
        self.navigationHistory = [.allDocs]
        self.navigationHistoryIndex = 0

        Task {
            await bootstrapFromDisk()
        }
    }

    public var currentDestination: WorkspaceDestination {
        tabs.first(where: { $0.id == activeTabId })?.destination ?? .allDocs
    }

    public var activeDocument: RoweDocument? {
        guard case .document(let id) = currentDestination else { return nil }
        return documents.first(where: { $0.id == id })
    }

    public var canGoBack: Bool { navigationHistoryIndex > 0 }
    public var canGoForward: Bool { navigationHistoryIndex + 1 < navigationHistory.count }

    private func bootstrapFromDisk() async {
        await syncScheduler.setDiagnosticsHandler { [weak self] diag in
            Task { @MainActor in
                self?.syncDiagnostics = diag
            }
        }
        await syncScheduler.setTransport(CallbackSyncTransport { [weak self] _ in
            guard let self else { return }
            try await self.pushBackendSyncIfSignedIn()
        })

        if let loaded = await database.load() {
            self.space = loaded.space
            self.folders = loaded.folders
            self.tags = loaded.tags
            self.sidebarSections = loaded.sidebarSections
            self.documents = loaded.documents
            self.deduplicateInboxAndSeedDocuments()
            self.sharedDocuments = loaded.sharedDocuments.filter {
                !($0.title == "Shared Feature Roadmap" && $0.sharedByName == "Collaborator")
            }
            self.connections = loaded.connections
            self.settings = loaded.settings
            UserDefaults.standard.set(loaded.settings.hasCompletedOnboarding, forKey: "rowe.hasCompletedOnboarding")
            self.vaultEnvelope = loaded.vaultEnvelope
            self.authSession = loaded.authSession
            self.lastSyncServerTimeMs = loaded.lastSyncServerTimeMs
            self.dirtyDocumentIds = Set(loaded.dirtyDocumentIds)
            self.pendingRemoteDeleteIds = Set(loaded.pendingRemoteDeleteIds)
            self.focusBehavior = loaded.focusBehavior
            if let savedURL = loaded.serverURL,
               !savedURL.isEmpty,
               savedURL != "http://localhost:8080" || loaded.authSession?.serverURL == "http://localhost:8080" {
                self.serverURL = RoweBackendClient.normalizeServerURL(savedURL)
            }
        } else {
            await database.flushNow(makeSnapshot())
        }

        let docs = self.documents
        await searchIndex.setCacheLimit(self.settings.searchCacheLimit)
        await searchIndex.rebuildFullIndex(
            documents: docs,
            folders: self.folders,
            tags: self.tags,
            connections: self.connections,
            sharedDocuments: self.sharedDocuments
        )
        self.searchIndexStats = await searchIndex.currentStats()
        self.stats = await database.computeStats(for: docs)
        recomputeAllTables()
        self.hasLoadedFromDisk = true

        if self.authSession != nil {
            startRealtimeSyncStream()
            Task {
                await self.refreshSessionAndSync()
            }
        }
    }

    // MARK: - Navigation & Tabs

    public func navigate(to destination: WorkspaceDestination, recordHistory: Bool = true) {
        if case .document(let previousDocId) = currentDestination,
           destination != .document(previousDocId) {
            pruneEmptyDocumentIfNeeded(docId: previousDocId)
        }

        if let idx = tabs.firstIndex(where: { $0.id == activeTabId }) {
            tabs[idx].destination = destination
        } else {
            let tab = BrowserTab(destination: destination)
            tabs.append(tab)
            activeTabId = tab.id
        }

        if case .document(let docId) = destination,
           let docIdx = documents.firstIndex(where: { $0.id == docId }) {
            documents[docIdx].lastViewedAt = Date()
            recomputeTables(in: documents[docIdx])
        }

        if recordHistory {
            if navigationHistoryIndex + 1 < navigationHistory.count {
                navigationHistory.removeSubrange((navigationHistoryIndex + 1)...)
            }
            if navigationHistory.last != destination {
                navigationHistory.append(destination)
                navigationHistoryIndex = navigationHistory.count - 1
            }
        }
    }

    public func goBack() {
        guard canGoBack else { return }
        navigationHistoryIndex -= 1
        navigate(to: navigationHistory[navigationHistoryIndex], recordHistory: false)
    }

    public func goForward() {
        guard canGoForward else { return }
        navigationHistoryIndex += 1
        navigate(to: navigationHistory[navigationHistoryIndex], recordHistory: false)
    }

    /// Debounced toggle preventing double-fires between AppKit menu equivalents and local key monitors.
    public func toggleLeftSidebar() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSidebarToggleUptime > 0.18 else { return }
        lastSidebarToggleUptime = now
        isLeftSidebarVisible.toggle()
    }

    public func openNewTab(destination: WorkspaceDestination = .allDocs) {
        let tab = BrowserTab(destination: destination)
        tabs.append(tab)
        activeTabId = tab.id
    }

    public func closeTab(id: String) {
        guard tabs.count > 1, let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if activeTabId == id {
            activeTabId = tabs[max(0, idx - 1)].id
        }
    }

    public func switchToTab(index: Int) {
        guard index >= 0, index < tabs.count else { return }
        activeTabId = tabs[index].id
    }

    public func tabTitle(for destination: WorkspaceDestination) -> String {
        switch destination {
        case .allDocs: return "All Docs"
        case .tasks: return "Tasks"
        case .calendar: return "Calendar"
        case .connections: return "Connections"
        case .sharedWithMe: return "Shared with Me"
        case .folder(let id): return folders.first(where: { $0.id == id })?.name ?? "Folder"
        case .tag(let name): return "#\(name)"
        case .trash: return "Trash"
        case .settings: return "Settings"
        case .document(let id):
            let doc = documents.first(where: { $0.id == id })
            let title = doc?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? "Untitled" : title
        }
    }

    // MARK: - Document CRUD

    public func isDocumentEmpty(_ doc: RoweDocument) -> Bool {
        guard !doc.isLocked, doc.encryptedPayload == nil, !doc.isTrashed else { return false }
        if !doc.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return doc.blocks.allSatisfy { block in
            block.kind == .text &&
            block.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            block.subblocks.isEmpty &&
            block.tableData == nil &&
            block.collectionData == nil
        }
    }

    /// Discards completely blank untitled notes so empty drafts are never saved or synced.
    public func pruneEmptyDocumentIfNeeded(docId: String) {
        guard let doc = documents.first(where: { $0.id == docId }), isDocumentEmpty(doc) else { return }
        dirtyDocumentIds.remove(docId)
        documents.removeAll(where: { $0.id == docId })
        schedulePersistence()
        rebuildSearchIndex()
    }

    @discardableResult
    public func createDocument(title: String = "", folderId: String? = nil, style: DocumentStyle = DocumentStyle(), openImmediately: Bool = true) -> RoweDocument {
        let docId = UUID().uuidString
        let initialBlock = Block(documentId: docId, content: "")
        let doc = RoweDocument(
            id: docId,
            spaceId: space.id,
            folderId: folderId,
            title: title,
            blocks: [initialBlock],
            style: style,
            authorName: space.authorName
        )
        documents.insert(doc, at: 0)
        // Only persist/sync non-empty documents immediately; blank notes stay transient until edited.
        if !isDocumentEmpty(doc) {
            persistAndReindex(doc)
        }
        if openImmediately {
            navigate(to: .document(doc.id))
            activeBlockId = initialBlock.id
        }
        return doc
    }

    public func updateDocumentTitle(docId: String, title: String) {
        guard let idx = documents.firstIndex(where: { $0.id == docId }) else { return }
        documents[idx].title = title
        documents[idx].updatedAt = Date()
        persistAndReindex(documents[idx])
    }

    public func updateDocumentStyle(docId: String, _ mutate: (inout DocumentStyle) -> Void) {
        guard let idx = documents.firstIndex(where: { $0.id == docId }) else { return }
        mutate(&documents[idx].style)
        documents[idx].updatedAt = Date()
        persistAndReindex(documents[idx])
    }

    public func toggleStarDocument(docId: String) {
        guard let idx = documents.firstIndex(where: { $0.id == docId }) else { return }
        documents[idx].isStarred.toggle()
        documents[idx].updatedAt = Date()
        persistAndReindex(documents[idx])
    }

    public func duplicateDocument(docId: String) {
        guard let source = documents.first(where: { $0.id == docId }) else { return }
        let newDocId = UUID().uuidString
        let clonedBlocks = source.blocks.map { cloneBlock($0, newDocumentId: newDocId) }
        let copy = RoweDocument(
            id: newDocId,
            spaceId: source.spaceId,
            folderId: source.folderId,
            title: source.displayTitle + " Copy",
            blocks: clonedBlocks,
            style: source.style,
            tags: source.tags,
            authorName: space.authorName
        )
        documents.insert(copy, at: 0)
        persistAndReindex(copy)
        navigate(to: .document(copy.id))
    }

    public func moveDocumentToTrash(docId: String) {
        guard let idx = documents.firstIndex(where: { $0.id == docId }) else { return }
        documents[idx].isTrashed = true
        documents[idx].updatedAt = Date()
        persistAndReindex(documents[idx], fastSync: true)
        if case .document(let currentId) = currentDestination, currentId == docId {
            navigate(to: .allDocs)
        }
    }

    public func restoreDocument(docId: String) {
        guard let idx = documents.firstIndex(where: { $0.id == docId }) else { return }
        documents[idx].isTrashed = false
        documents[idx].updatedAt = Date()
        persistAndReindex(documents[idx], fastSync: true)
    }

    public func permanentlyDeleteDocument(docId: String) {
        dirtyDocumentIds.remove(docId)
        documents.removeAll(where: { $0.id == docId })
        if authSession != nil {
            pendingRemoteDeleteIds.insert(docId)
        }
        if case .document(let currentId) = currentDestination, currentId == docId {
            navigate(to: .allDocs)
        }
        schedulePersistence()
        rebuildSearchIndex()
        if authSession != nil {
            Task {
                await deleteRemoteDocument(docId: docId)
            }
        }
    }

    public func moveDocument(docId: String, toFolderId folderId: String?) {
        guard let idx = documents.firstIndex(where: { $0.id == docId }) else { return }
        documents[idx].folderId = folderId
        documents[idx].updatedAt = Date()
        persistAndReindex(documents[idx])
    }

    // MARK: - Block Operations, Selection State & Undo

    private func undoStack(for docId: String) -> UndoCoordinator<EditorUndoSnapshot> {
        if let existing = docUndoStacks[docId] { return existing }
        let created = UndoCoordinator<EditorUndoSnapshot>()
        docUndoStacks[docId] = created
        return created
    }

    public func breakUndoGrouping(in docId: String) {
        undoStack(for: docId).breakGrouping()
    }

    /// Returns flat visible blocks respecting Craft's flat-indentation toggle folding.
    public func visibleBlocks(in docId: String) -> [Block] {
        guard let doc = documents.first(where: { $0.id == docId }) else { return [] }
        var visible: [Block] = []
        var collapsedIndentFloor: Int? = nil

        for block in doc.blocks where block.deletedAt == nil {
            if let floor = collapsedIndentFloor {
                if block.indentLevel > floor {
                    continue
                } else {
                    collapsedIndentFloor = nil
                }
            }
            visible.append(block)
            if block.listStyle == .toggle && !block.isToggleExpanded {
                collapsedIndentFloor = block.indentLevel
            }
        }
        return visible
    }

    public func mutateBlocks(in docId: String, coalesceUndo: Bool = false, _ transform: (inout [Block]) -> Void) {
        guard let idx = documents.firstIndex(where: { $0.id == docId }) else { return }
        let beforeSnapshot = EditorUndoSnapshot(
            blocks: documents[idx].blocks,
            activeBlockId: activeBlockId,
            selectedBlockIds: selectedBlockIds,
            caretUTF16Offset: activeCaretUTF16Offset
        )
        undoStack(for: docId).record(before: beforeSnapshot, coalesceWindow: coalesceUndo ? 1.0 : 0.0)
        transform(&documents[idx].blocks)
        if documents[idx].blocks.isEmpty {
            let fresh = Block(documentId: docId, content: "")
            documents[idx].blocks.append(fresh)
            activeBlockId = fresh.id
        }
        documents[idx].updatedAt = Date()
        recomputeTables(in: documents[idx])
        persistAndReindex(documents[idx])
    }

    public func undo(in docId: String) {
        guard let idx = documents.firstIndex(where: { $0.id == docId }) else { return }
        let currentSnapshot = EditorUndoSnapshot(
            blocks: documents[idx].blocks,
            activeBlockId: activeBlockId,
            selectedBlockIds: selectedBlockIds,
            caretUTF16Offset: activeCaretUTF16Offset
        )
        guard let restored = undoStack(for: docId).undo(current: currentSnapshot) else { return }
        applyUndoSnapshot(restored, docIndex: idx)
    }

    public func redo(in docId: String) {
        guard let idx = documents.firstIndex(where: { $0.id == docId }) else { return }
        let currentSnapshot = EditorUndoSnapshot(
            blocks: documents[idx].blocks,
            activeBlockId: activeBlockId,
            selectedBlockIds: selectedBlockIds,
            caretUTF16Offset: activeCaretUTF16Offset
        )
        guard let restored = undoStack(for: docId).redo(current: currentSnapshot) else { return }
        applyUndoSnapshot(restored, docIndex: idx)
    }

    private func applyUndoSnapshot(_ snapshot: EditorUndoSnapshot, docIndex: Int) {
        documents[docIndex].blocks = snapshot.blocks
        documents[docIndex].updatedAt = Date()
        activeBlockId = snapshot.activeBlockId
        selectedBlockIds = snapshot.selectedBlockIds
        if !snapshot.selectedBlockIds.isEmpty {
            editorSelectionMode = .blockSelection
        } else if let blockId = snapshot.activeBlockId {
            editorSelectionMode = .inlineSelection
            caretRequest = BlockCaretRequest(blockId: blockId, utf16Offset: snapshot.caretUTF16Offset)
        } else {
            editorSelectionMode = .noSelection
        }
        recomputeTables(in: documents[docIndex])
        persistAndReindex(documents[docIndex])
    }

    // MARK: - Selection & Navigation State Machine

    public func enterInlineEditing(blockId: String, utf16Offset: Int? = nil, desiredX: Double? = nil, fromBottom: Bool = false) {
        activeBlockId = blockId
        selectedBlockIds.removeAll()
        selectionAnchorBlockId = blockId
        editorSelectionMode = .inlineSelection
        if let utf16Offset { activeCaretUTF16Offset = utf16Offset }
        caretRequest = BlockCaretRequest(blockId: blockId, utf16Offset: utf16Offset, desiredX: desiredX, fromBottom: fromBottom)
    }

    public func focusTitle(desiredX: Double? = nil) {
        selectedBlockIds.removeAll()
        editorSelectionMode = .titleInlineSelection
        caretRequest = BlockCaretRequest(blockId: nil, desiredX: desiredX, fromBottom: true)
    }

    public func selectSingleBlock(_ blockId: String) {
        activeBlockId = blockId
        selectedBlockIds = [blockId]
        selectionAnchorBlockId = blockId
        editorSelectionMode = .blockSelection
    }

    public func toggleBlockSelection(_ blockId: String) {
        if selectedBlockIds.contains(blockId) {
            selectedBlockIds.remove(blockId)
            if selectedBlockIds.isEmpty {
                editorSelectionMode = .noSelection
            }
        } else {
            selectedBlockIds.insert(blockId)
            activeBlockId = blockId
            if selectionAnchorBlockId == nil { selectionAnchorBlockId = blockId }
            editorSelectionMode = .blockSelection
        }
    }

    public func extendBlockSelection(in docId: String, to targetBlockId: String) {
        let visible = visibleBlocks(in: docId)
        let anchorId = selectionAnchorBlockId ?? activeBlockId ?? targetBlockId
        guard let anchorIdx = visible.firstIndex(where: { $0.id == anchorId }),
              let targetIdx = visible.firstIndex(where: { $0.id == targetBlockId }) else {
            selectSingleBlock(targetBlockId)
            return
        }
        let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
        selectedBlockIds = Set(visible[range].map(\.id))
        activeBlockId = targetBlockId
        selectionAnchorBlockId = anchorId
        editorSelectionMode = .blockSelection
    }

    public func selectAllBlocks(in docId: String) {
        let visible = visibleBlocks(in: docId)
        selectedBlockIds = Set(visible.map(\.id))
        if activeBlockId == nil { activeBlockId = visible.first?.id }
        editorSelectionMode = .blockSelection
    }

    public func clearBlockSelection() {
        selectedBlockIds.removeAll()
        selectionAnchorBlockId = nil
        if editorSelectionMode == .blockSelection {
            editorSelectionMode = .noSelection
        }
    }

    /// Jumps vertically between visible blocks preserving horizontal X coordinate (or extending block selection).
    public func focusAdjacentBlock(in docId: String, from blockId: String, direction: Int, desiredX: Double?, extendSelection: Bool = false) {
        let visible = visibleBlocks(in: docId)
        guard let currentIdx = visible.firstIndex(where: { $0.id == blockId }) else { return }
        let nextIdx = currentIdx + direction

        if nextIdx < 0 {
            if !extendSelection {
                focusTitle(desiredX: desiredX)
            }
            return
        }
        guard nextIdx < visible.count else { return }
        let target = visible[nextIdx]

        if extendSelection {
            if selectionAnchorBlockId == nil { selectionAnchorBlockId = blockId }
            extendBlockSelection(in: docId, to: target.id)
            return
        }

        if target.isEditableTextBlock {
            enterInlineEditing(blockId: target.id, desiredX: desiredX, fromBottom: direction < 0)
        } else {
            selectSingleBlock(target.id)
        }
    }

    // MARK: - v2 Smart Block Insertion, Split, Backspace & Forward Delete

    @discardableResult
    public func insertBlock(in docId: String, after blockId: String?, block newBlock: Block? = nil) -> Block {
        let created = newBlock ?? Block(documentId: docId, content: "")
        mutateBlocks(in: docId) { blocks in
            if let afterId = blockId, let idx = blocks.firstIndex(where: { $0.id == afterId }) {
                blocks.insert(created, at: idx + 1)
            } else {
                blocks.append(created)
            }
        }
        if created.isEditableTextBlock {
            enterInlineEditing(blockId: created.id, utf16Offset: 0)
        } else {
            selectSingleBlock(created.id)
        }
        return created
    }

    /// Inserts a non-text/structured block cleanly: replaces an empty plain body block instead of leaving
    /// blank ghost lines, and guarantees an editable body block right below when requested.
    @discardableResult
    public func insertStructuredBlock(in docId: String, after targetId: String?, block newBlock: Block, focusTrailingBody: Bool = false) -> Block {
        var trailingBodyId: String?
        mutateBlocks(in: docId) { blocks in
            let insertIndex: Int
            if let targetId, let idx = blocks.firstIndex(where: { $0.id == targetId }) {
                if blocks[idx].isEmptyPlainBody {
                    blocks[idx] = newBlock
                    insertIndex = idx
                } else {
                    blocks.insert(newBlock, at: idx + 1)
                    insertIndex = idx + 1
                }
            } else {
                blocks.append(newBlock)
                insertIndex = blocks.count - 1
            }

            if focusTrailingBody {
                let nextIdx = insertIndex + 1
                if nextIdx < blocks.count && blocks[nextIdx].isEditableTextBlock {
                    trailingBodyId = blocks[nextIdx].id
                } else {
                    let body = Block(documentId: docId, content: "")
                    blocks.insert(body, at: nextIdx)
                    trailingBodyId = body.id
                }
            }
        }

        if let trailingBodyId {
            enterInlineEditing(blockId: trailingBodyId, utf16Offset: 0)
        } else {
            selectSingleBlock(newBlock.id)
        }
        return newBlock
    }

    /// Updates the selected separator in place if one is selected; otherwise inserts a separator cleanly
    /// after the active block and focuses a fresh body block below it.
    public func insertOrUpdateSeparator(in docId: String, after targetId: String?, style: SeparatorStyle) {
        if let doc = documents.first(where: { $0.id == docId }),
           let activeId = targetId ?? activeBlockId,
           let activeBlock = doc.blocks.first(where: { $0.id == activeId }),
           activeBlock.kind == .line {
            updateBlock(in: docId, blockId: activeId) { $0.separatorStyle = style }
            selectSingleBlock(activeId)
            return
        }
        let sep = Block(documentId: docId, kind: .line, content: "---", separatorStyle: style)
        _ = insertStructuredBlock(in: docId, after: targetId ?? activeBlockId, block: sep, focusTrailingBody: true)
    }

    /// Craft Spec 02 §2.1 Return handler: handles empty-list outdent/exit, decoration exit, and mid-text UTF-16 split.
    public func splitBlock(in docId: String, blockId: String, atUTF16Offset offset: Int) {
        guard let doc = documents.first(where: { $0.id == docId }),
              let idx = doc.blocks.firstIndex(where: { $0.id == blockId }) else { return }
        let block = doc.blocks[idx]
        let utf16Len = block.content.utf16.count
        let clampedOffset = max(0, min(offset, utf16Len))

        // Empty list item: outdent first, then exit list (and reset custom block color)
        if utf16Len == 0 && block.listStyle != .none {
            mutateBlocks(in: docId) { blocks in
                guard let i = blocks.firstIndex(where: { $0.id == blockId }) else { return }
                if blocks[i].indentLevel > 0 {
                    blocks[i].indentLevel -= 1
                } else {
                    blocks[i].listStyle = .none
                    blocks[i].userDefinedListNumber = nil
                    blocks[i].task = nil
                    blocks[i].color = .primary
                }
            }
            enterInlineEditing(blockId: blockId, utf16Offset: 0)
            return
        }

        // Empty callout/focus decoration: exit decoration
        if utf16Len == 0 && block.decoration != .none {
            mutateBlocks(in: docId) { blocks in
                guard let i = blocks.firstIndex(where: { $0.id == blockId }) else { return }
                blocks[i].decoration = .none
                blocks[i].color = .primary
            }
            enterInlineEditing(blockId: blockId, utf16Offset: 0)
            return
        }

        let nsContent = block.content as NSString
        let leadingText = nsContent.substring(to: clampedOffset)
        let trailingText = nsContent.substring(from: clampedOffset)
        let (leadingRuns, trailingRuns) = TextRunAttributes.split(block.runs, at: clampedOffset, totalLength: utf16Len)

        let nextStyle: BlockTextStyle = {
            if clampedOffset == utf16Len && block.textStyle != .body {
                return .body
            }
            return trailingText.isEmpty ? .body : block.textStyle
        }()

        let nextListStyle: BlockListStyle = (block.listStyle == .toggle && clampedOffset == utf16Len) ? .none : block.listStyle
        // Block color stays scoped to the current block when starting a fresh paragraph,
        // while continuing naturally across items in the same list (bullets/numbered/todos).
        let nextColor: BlockColor = (nextListStyle != .none || !trailingText.isEmpty) ? block.color : .primary

        var newBlock = Block(
            documentId: docId,
            kind: .text,
            content: trailingText,
            runs: trailingRuns,
            textStyle: nextStyle,
            listStyle: nextListStyle,
            indentLevel: block.indentLevel,
            alignment: block.alignment,
            decoration: block.decoration,
            color: nextColor,
            fontOverride: block.fontOverride
        )
        if newBlock.listStyle == .todo {
            newBlock.task = TaskMetadata(state: .pending)
        }

        mutateBlocks(in: docId) { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == blockId }) else { return }
            blocks[i].content = leadingText
            blocks[i].runs = leadingRuns
            blocks.insert(newBlock, at: i + 1)
        }
        enterInlineEditing(blockId: newBlock.id, utf16Offset: 0)
    }

    /// Craft Spec 02 §2.2 Backspace at offset 0 strict 5-step precedence.
    public func backspaceAtStart(in docId: String, blockId: String) {
        guard let doc = documents.first(where: { $0.id == docId }),
              let idx = doc.blocks.firstIndex(where: { $0.id == blockId }) else { return }
        let block = doc.blocks[idx]

        // 1. Clear list style
        if block.listStyle != .none {
            updateBlock(in: docId, blockId: blockId) { blk in
                blk.listStyle = .none
                blk.userDefinedListNumber = nil
                blk.task = nil
            }
            enterInlineEditing(blockId: blockId, utf16Offset: 0)
            return
        }
        // 2. Clear decoration
        if block.decoration != .none {
            updateBlock(in: docId, blockId: blockId) { $0.decoration = .none }
            enterInlineEditing(blockId: blockId, utf16Offset: 0)
            return
        }
        // 3. Decrease indentation
        if block.indentLevel > 0 {
            updateBlock(in: docId, blockId: blockId) { $0.indentLevel -= 1 }
            enterInlineEditing(blockId: blockId, utf16Offset: 0)
            return
        }
        // 4. Reset heading/caption style when empty
        if block.textStyle != .body && block.textStyle != .pageRegular && block.textStyle != .pageCard && block.content.isEmpty {
            updateBlock(in: docId, blockId: blockId) { $0.textStyle = .body }
            enterInlineEditing(blockId: blockId, utf16Offset: 0)
            return
        }

        // 5. Merge with previous visible block (or delete empty first block / select non-text previous block)
        let visible = visibleBlocks(in: docId)
        guard let visIdx = visible.firstIndex(where: { $0.id == blockId }) else { return }
        if visIdx == 0 {
            if block.content.isEmpty && visible.count > 1 {
                let next = visible[1]
                mutateBlocks(in: docId) { blocks in
                    blocks.removeAll(where: { $0.id == blockId })
                }
                if next.isEditableTextBlock {
                    enterInlineEditing(blockId: next.id, utf16Offset: 0)
                } else {
                    selectSingleBlock(next.id)
                }
            }
            return
        }
        let prev = visible[visIdx - 1]

        if prev.isEditableTextBlock {
            let joinOffset = prev.content.utf16.count
            let shiftedRuns = TextRunAttributes.shifted(block.runs, by: joinOffset)
            mutateBlocks(in: docId) { blocks in
                guard let prevIdx = blocks.firstIndex(where: { $0.id == prev.id }),
                      let curIdx = blocks.firstIndex(where: { $0.id == blockId }) else { return }
                blocks[prevIdx].content += block.content
                blocks[prevIdx].runs = TextRunAttributes.normalize(blocks[prevIdx].runs + shiftedRuns, utf16Length: blocks[prevIdx].content.utf16.count)
                blocks.remove(at: curIdx)
            }
            enterInlineEditing(blockId: prev.id, utf16Offset: joinOffset)
        } else if block.content.isEmpty {
            mutateBlocks(in: docId) { blocks in
                blocks.removeAll(where: { $0.id == blockId })
            }
            selectSingleBlock(prev.id)
        } else {
            selectSingleBlock(prev.id)
        }
    }

    /// Craft Spec 02 §2.2 Forward Delete at end of block.
    public func forwardDeleteAtEnd(in docId: String, blockId: String) {
        let visible = visibleBlocks(in: docId)
        guard let visIdx = visible.firstIndex(where: { $0.id == blockId }), visIdx + 1 < visible.count else { return }
        let current = visible[visIdx]
        let next = visible[visIdx + 1]

        if next.isEditableTextBlock {
            let joinOffset = current.content.utf16.count
            let shiftedRuns = TextRunAttributes.shifted(next.runs, by: joinOffset)
            mutateBlocks(in: docId) { blocks in
                guard let curIdx = blocks.firstIndex(where: { $0.id == blockId }),
                      let nextIdx = blocks.firstIndex(where: { $0.id == next.id }) else { return }
                blocks[curIdx].content += next.content
                blocks[curIdx].runs = TextRunAttributes.normalize(blocks[curIdx].runs + shiftedRuns, utf16Length: blocks[curIdx].content.utf16.count)
                blocks.remove(at: nextIdx)
            }
            enterInlineEditing(blockId: blockId, utf16Offset: joinOffset)
        } else if next.kind == .line || next.content.isEmpty {
            mutateBlocks(in: docId) { blocks in
                blocks.removeAll(where: { $0.id == next.id })
            }
            enterInlineEditing(blockId: blockId, utf16Offset: current.content.utf16.count)
        } else {
            selectSingleBlock(next.id)
        }
    }

    public func updateBlock(in docId: String, blockId: String, coalesceUndo: Bool = false, _ mutate: (inout Block) -> Void) {
        var mutatedTaskTitle: String? = nil
        mutateBlocks(in: docId, coalesceUndo: coalesceUndo) { blocks in
            _ = Self.mutateBlockRecursive(in: &blocks, id: blockId) { block in
                mutate(&block)
                if block.isTask {
                    mutatedTaskTitle = block.content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        if let title = mutatedTaskTitle {
            scheduleDebouncedCloudSync(delayOverride: 0.25)
            onTaskMutatedForLiveSync?(title.isEmpty ? "Task updated" : title)
        }
    }

    public func deleteBlock(in docId: String, blockId: String) {
        deleteBlocks(in: docId, blockIds: [blockId])
    }

    public func deleteBlocks(in docId: String, blockIds: Set<String>) {
        guard !blockIds.isEmpty else { return }
        var fallbackBlock: Block?
        var deletedAnyTask = false
        let now = Date()
        mutateBlocks(in: docId) { blocks in
            let firstRemovedIdx = blocks.firstIndex(where: { blockIds.contains($0.id) }) ?? 0
            // Tombstone task blocks instead of hard-removing them so CRDT merge propagates deletions
            // across offline devices without resurrecting deleted tasks.
            for idx in blocks.indices where blockIds.contains(blocks[idx].id) {
                if blocks[idx].isTaskOrTombstone {
                    blocks[idx].deletedAt = now
                    blocks[idx].updatedAt = now
                    deletedAnyTask = true
                }
            }
            blocks.removeAll(where: { blockIds.contains($0.id) && !$0.isTaskOrTombstone })
            for id in blockIds {
                _ = Self.tombstoneOrRemoveBlockRecursive(in: &blocks, id: id, now: now, deletedTask: &deletedAnyTask)
            }
            let liveBlocks = blocks.filter { $0.deletedAt == nil }
            if liveBlocks.isEmpty {
                let fresh = Block(documentId: docId, content: "")
                blocks.append(fresh)
                fallbackBlock = fresh
            } else {
                let safeIdx = max(0, min(firstRemovedIdx - 1, liveBlocks.count - 1))
                fallbackBlock = liveBlocks[safeIdx]
            }
        }
        if deletedAnyTask {
            scheduleDebouncedCloudSync(delayOverride: 0.05)
            onTaskMutatedForLiveSync?("Task deleted")
        }
        selectedBlockIds.removeAll()
        if let fb = fallbackBlock {
            if fb.isEditableTextBlock {
                enterInlineEditing(blockId: fb.id, utf16Offset: fb.content.utf16.count)
            } else {
                selectSingleBlock(fb.id)
            }
        }
    }

    public func duplicateBlock(in docId: String, blockId: String) {
        duplicateBlocks(in: docId, blockIds: [blockId])
    }

    public func duplicateBlocks(in docId: String, blockIds: Set<String>) {
        guard !blockIds.isEmpty else { return }
        var newIds: Set<String> = []
        mutateBlocks(in: docId) { blocks in
            let indices = blocks.indices.filter { blockIds.contains(blocks[$0].id) }
            guard let lastIdx = indices.last else { return }
            let clones = indices.map { cloneBlock(blocks[$0], newDocumentId: docId) }
            newIds = Set(clones.map(\.id))
            blocks.insert(contentsOf: clones, at: lastIdx + 1)
        }
        if newIds.count == 1, let onlyId = newIds.first {
            enterInlineEditing(blockId: onlyId, utf16Offset: 0)
        } else if !newIds.isEmpty {
            selectedBlockIds = newIds
            activeBlockId = newIds.first
            editorSelectionMode = .blockSelection
        }
    }

    public func indentBlocks(in docId: String, blockIds: Set<String>, delta: Int) {
        guard !blockIds.isEmpty else { return }
        mutateBlocks(in: docId) { blocks in
            for idx in blocks.indices where blockIds.contains(blocks[idx].id) {
                blocks[idx].indentLevel = max(0, min(8, blocks[idx].indentLevel + delta))
            }
        }
    }

    public func moveBlock(in docId: String, blockId: String, offset: Int) {
        moveBlocks(in: docId, blockIds: [blockId], offset: offset)
    }

    public func moveBlocks(in docId: String, blockIds: Set<String>, offset: Int) {
        guard !blockIds.isEmpty, offset != 0 else { return }
        mutateBlocks(in: docId) { blocks in
            let indices = blocks.indices.filter { blockIds.contains(blocks[$0].id) }
            guard let first = indices.first, let last = indices.last else { return }
            if offset < 0 && first == 0 { return }
            if offset > 0 && last == blocks.count - 1 { return }
            let extracted = indices.map { blocks[$0] }
            for i in indices.reversed() { blocks.remove(at: i) }
            let insertAt = max(0, min(blocks.count, first + offset))
            blocks.insert(contentsOf: extracted, at: insertAt)
        }
    }

    public func reorderBlock(in docId: String, sourceId: String, targetId: String, placeAfter: Bool) {
        guard sourceId != targetId else { return }
        mutateBlocks(in: docId) { blocks in
            guard let fromIdx = blocks.firstIndex(where: { $0.id == sourceId }) else { return }
            let item = blocks.remove(at: fromIdx)
            guard let targetIdx = blocks.firstIndex(where: { $0.id == targetId }) else {
                blocks.append(item)
                return
            }
            let dest = placeAfter ? min(blocks.count, targetIdx + 1) : targetIdx
            blocks.insert(item, at: dest)
        }
    }

    public func moveBlockToEdge(in docId: String, blockId: String, top: Bool) {
        mutateBlocks(in: docId) { blocks in
            guard let idx = blocks.firstIndex(where: { $0.id == blockId }) else { return }
            let item = blocks.remove(at: idx)
            blocks.insert(item, at: top ? 0 : blocks.count)
        }
    }

    /// Applies a color to the active inline text selection if text is selected, otherwise to the whole active/selected block(s).
    public func applyColorToSelectionOrBlocks(in docId: String, color: BlockColor) {
        if editorSelectionMode == .inlineSelection,
           let blockId = activeBlockId,
           let loc = activeCaretUTF16Offset,
           activeSelectionLength > 0 {
            let selLen = activeSelectionLength
            updateBlock(in: docId, blockId: blockId) { blk in
                var runs = blk.runs
                let hex: String? = (color == .primary) ? nil : color.hex
                if let hex {
                    runs.append(TextRunAttributes(location: loc, length: selLen, textColorHex: hex))
                } else {
                    runs = runs.map { r in
                        var c = r
                        if r.location < loc + selLen && r.upperBound > loc { c.textColorHex = nil }
                        return c
                    }
                }
                blk.runs = TextRunAttributes.normalize(runs, utf16Length: blk.content.utf16.count)
            }
            return
        }
        let targets: Set<String> = selectedBlockIds.isEmpty ? (activeBlockId.map { [$0] } ?? []) : selectedBlockIds
        guard !targets.isEmpty else { return }
        mutateBlocks(in: docId) { blocks in
            for i in blocks.indices where targets.contains(blocks[i].id) {
                blocks[i].color = color
                blocks[i].runs = TextRunAttributes.normalize(blocks[i].runs.map { var r = $0; r.textColorHex = nil; return r }, utf16Length: blocks[i].content.utf16.count)
            }
        }
    }

    /// Toggles bold/italic/strikethrough/code on selected UTF-16 range if non-empty, else on whole active/selected block(s).
    public func toggleStyleFlagOnSelectionOrBlocks(in docId: String, flag: String) {
        if editorSelectionMode == .inlineSelection,
           let blockId = activeBlockId,
           let loc = activeCaretUTF16Offset,
           activeSelectionLength > 0 {
            let selLen = activeSelectionLength
            updateBlock(in: docId, blockId: blockId) { blk in
                var runs = blk.runs
                let hasFlag = runs.contains { r in
                    r.location <= loc && r.upperBound >= loc + selLen && {
                        switch flag {
                        case "bold": r.isBold
                        case "italic": r.isItalic
                        case "strike": r.isStrikethrough
                        case "code": r.isCode
                        default: false
                        }
                    }()
                }
                if !hasFlag {
                    var added = TextRunAttributes(location: loc, length: selLen)
                    switch flag {
                    case "bold": added.isBold = true
                    case "italic": added.isItalic = true
                    case "strike": added.isStrikethrough = true
                    case "code": added.isCode = true
                    default: break
                    }
                    runs.append(added)
                } else {
                    runs = runs.map { r in
                        var c = r
                        if r.location < loc + selLen && r.upperBound > loc {
                            switch flag {
                            case "bold": c.isBold = false
                            case "italic": c.isItalic = false
                            case "strike": c.isStrikethrough = false
                            case "code": c.isCode = false
                            default: break
                            }
                        }
                        return c
                    }
                }
                blk.runs = TextRunAttributes.normalize(runs, utf16Length: blk.content.utf16.count)
            }
            return
        }
        let targets: Set<String> = selectedBlockIds.isEmpty ? (activeBlockId.map { [$0] } ?? []) : selectedBlockIds
        guard !targets.isEmpty else { return }
        mutateBlocks(in: docId) { blocks in
            for i in blocks.indices where targets.contains(blocks[i].id) {
                switch flag {
                case "bold": blocks[i].isBold.toggle()
                case "italic": blocks[i].isItalic.toggle()
                case "strike": blocks[i].isStrikethrough.toggle()
                case "code": blocks[i].isInlineCode.toggle()
                default: break
                }
            }
        }
    }

    /// Multi-line paste helper: inserts lines as structured blocks in a single undo step.
    public func pasteMultilineText(in docId: String, blockId: String, atUTF16Offset offset: Int, text: String) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.count > 1 else { return }
        guard let doc = documents.first(where: { $0.id == docId }),
              let idx = doc.blocks.firstIndex(where: { $0.id == blockId }) else { return }
        let block = doc.blocks[idx]
        let nsContent = block.content as NSString
        let clamped = max(0, min(offset, nsContent.length))
        let head = nsContent.substring(to: clamped)
        let tail = nsContent.substring(from: clamped)
        let (headRuns, tailRuns) = TextRunAttributes.split(block.runs, at: clamped, totalLength: nsContent.length)

        var lastBlockId = blockId
        var lastCaretOffset = 0

        mutateBlocks(in: docId) { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == blockId }) else { return }
            blocks[i].content = head + lines[0]
            blocks[i].runs = TextRunAttributes.normalize(headRuns, utf16Length: blocks[i].content.utf16.count)

            var inserted: [Block] = []
            for lineIdx in 1..<lines.count {
                let isLast = (lineIdx == lines.count - 1)
                let rawLine = lines[lineIdx]
                let bodyText = isLast ? (rawLine + tail) : rawLine
                var newBlk = Block(documentId: docId, content: bodyText, indentLevel: block.indentLevel)
                if isLast && !tailRuns.isEmpty {
                    newBlk.runs = TextRunAttributes.normalize(TextRunAttributes.shifted(tailRuns, by: rawLine.utf16.count), utf16Length: bodyText.utf16.count)
                }
                inserted.append(newBlk)
                if isLast {
                    lastBlockId = newBlk.id
                    lastCaretOffset = rawLine.utf16.count
                }
            }
            blocks.insert(contentsOf: inserted, at: i + 1)
        }
        enterInlineEditing(blockId: lastBlockId, utf16Offset: lastCaretOffset)
    }

    // MARK: - Tasks & Calendar

    public func allTasks() -> [ResolvedTaskItem] {
        var result: [ResolvedTaskItem] = []
        for doc in documents where !doc.isTrashed {
            func collect(_ blocks: [Block]) {
                for b in blocks {
                    if b.isTask {
                        result.append(ResolvedTaskItem(
                            block: b,
                            documentId: doc.id,
                            documentTitle: doc.displayTitle,
                            isInbox: b.task?.isInbox ?? (doc.title == "Tasks Inbox")
                        ))
                    }
                    collect(b.subblocks)
                }
            }
            collect(doc.blocks)
        }
        return result
    }

    public func setTaskState(docId: String, blockId: String, state: TaskCompletionState) {
        updateBlock(in: docId, blockId: blockId) { block in
            if block.task == nil {
                block.task = TaskMetadata(state: .pending)
            }
            block.listStyle = .todo
            block.task?.applyStateTransition(to: state)
        }
        scheduleDebouncedCloudSync(delayOverride: 0.05)
    }

    @discardableResult
    public func addInboxTask(
        title: String,
        scheduleDate: Date? = nil,
        deadlineDate: Date? = nil,
        repeatRule: RepeatRule? = nil,
        attachedImagesBase64: [String] = []
    ) -> ResolvedTaskItem {
        let inboxDoc: RoweDocument
        if let existing = documents.first(where: { $0.title == "Tasks Inbox" && !$0.isTrashed }) {
            inboxDoc = existing
        } else {
            inboxDoc = createDocument(title: "Tasks Inbox", folderId: folders.first?.id, openImmediately: false)
        }
        let block = Block(
            documentId: inboxDoc.id,
            content: title,
            listStyle: .todo,
            task: TaskMetadata(
                state: .pending,
                scheduleDate: scheduleDate,
                deadlineDate: deadlineDate,
                repeatRule: repeatRule,
                isInbox: true,
                attachedImagesBase64: attachedImagesBase64
            )
        )
        mutateBlocks(in: inboxDoc.id) { blocks in
            blocks.append(block)
        }
        scheduleDebouncedCloudSync(delayOverride: 0.05)
        onTaskMutatedForLiveSync?(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New task" : title)
        let item = ResolvedTaskItem(block: block, documentId: inboxDoc.id, documentTitle: inboxDoc.displayTitle, isInbox: true)
        if !inboxDoc.isLocked, let candidate = NudgeCandidateTask(from: item, in: inboxDoc) {
            Task { await self.estimateAndCacheDuration(for: candidate) }
        }
        return item
    }

    // MARK: - Folders, Connections, Settings

    public func createFolder(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folders.append(Folder(spaceId: space.id, name: trimmed, sortOrder: folders.count))
        schedulePersistence()
    }

    public func deleteFolder(id: String) {
        folders.removeAll(where: { $0.id == id })
        for idx in documents.indices where documents[idx].folderId == id {
            documents[idx].folderId = nil
        }
        if case .folder(let currentId) = currentDestination, currentId == id {
            navigate(to: .allDocs)
        }
        schedulePersistence()
    }

    public func reorderFolder(sourceId: String, targetId: String) {
        guard sourceId != targetId else { return }
        var ordered = folders.sorted(by: { $0.sortOrder < $1.sortOrder })
        guard let fromIdx = ordered.firstIndex(where: { $0.id == sourceId }),
              let toIdx = ordered.firstIndex(where: { $0.id == targetId }) else { return }
        let moved = ordered.remove(at: fromIdx)
        ordered.insert(moved, at: toIdx)
        for i in ordered.indices { ordered[i].sortOrder = i }
        folders = ordered
        schedulePersistence()
    }

    public func reorderStarredDocument(sourceId: String, targetId: String) {
        guard sourceId != targetId,
              let fromIdx = documents.firstIndex(where: { $0.id == sourceId }),
              let toIdx = documents.firstIndex(where: { $0.id == targetId }) else { return }
        let moved = documents.remove(at: fromIdx)
        documents.insert(moved, at: toIdx)
        schedulePersistence()
    }

    public func unpinTag(id: String) {
        guard let idx = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[idx].isPinned = false
        schedulePersistence()
    }

    public func reorderTag(sourceId: String, targetId: String) {
        guard sourceId != targetId,
              let fromIdx = tags.firstIndex(where: { $0.id == sourceId }),
              let toIdx = tags.firstIndex(where: { $0.id == targetId }) else { return }
        let moved = tags.remove(at: fromIdx)
        tags.insert(moved, at: toIdx)
        schedulePersistence()
    }

    public func reorderOrRescheduleTask(sourceBlockId: String, targetBlockId: String?, targetDay: Date) {
        guard let sourceDocIdx = documents.firstIndex(where: { $0.blocks.contains(where: { $0.id == sourceBlockId }) }),
              let sourceBlockIdx = documents[sourceDocIdx].blocks.firstIndex(where: { $0.id == sourceBlockId }) else {
            return
        }

        var block = documents[sourceDocIdx].blocks[sourceBlockIdx]
        var meta = block.task ?? TaskMetadata(state: .pending, isInbox: documents[sourceDocIdx].title == "Tasks Inbox")
        meta.scheduleDate = Calendar.current.startOfDay(for: targetDay)
        block.task = meta
        documents[sourceDocIdx].blocks[sourceBlockIdx] = block

        if let targetBlockId, sourceBlockId != targetBlockId,
           let targetBlockIdx = documents[sourceDocIdx].blocks.firstIndex(where: { $0.id == targetBlockId }) {
            let moved = documents[sourceDocIdx].blocks.remove(at: sourceBlockIdx)
            documents[sourceDocIdx].blocks.insert(moved, at: min(targetBlockIdx, documents[sourceDocIdx].blocks.count))
        }

        documents[sourceDocIdx].updatedAt = Date()
        persistAndReindex(documents[sourceDocIdx], fastSync: true)
        onTaskMutatedForLiveSync?(block.content.isEmpty ? "Task rescheduled" : block.content)
    }

    public func toggleSidebarSection(_ type: SidebarSectionType) {
        if let idx = sidebarSections.firstIndex(where: { $0.type == type }) {
            sidebarSections[idx].isCollapsed.toggle()
            schedulePersistence()
        }
    }

    public func makeDraftConnection(kind: ConnectionKind, name: String? = nil) -> ConnectionItem {
        let defaultName = kind == .mcp ? "MCP for All Documents" : "API for Workspace"
        let slug = UUID().uuidString.prefix(8).lowercased()
        return ConnectionItem(
            kind: kind,
            name: name ?? defaultName,
            endpointURL: "https://connect.rowe.local/\(kind == .mcp ? "mcp" : "api")/\(slug)",
            documentScope: kind == .mcp ? .allDocuments : .dailyNotesAndTasks,
            permission: .readAndWrite,
            accessMode: kind == .mcp ? .localOnly : .publicAccess
        )
    }

    public func saveConnection(_ item: ConnectionItem) {
        if let idx = connections.firstIndex(where: { $0.id == item.id }) {
            connections[idx] = item
        } else {
            connections.append(item)
        }
        schedulePersistence()
    }

    public func addConnection(kind: ConnectionKind, name: String? = nil) -> ConnectionItem {
        let item = makeDraftConnection(kind: kind, name: name)
        connections.append(item)
        schedulePersistence()
        return item
    }

    public func updateConnection(_ updated: ConnectionItem) {
        guard let idx = connections.firstIndex(where: { $0.id == updated.id }) else { return }
        connections[idx] = updated
        schedulePersistence()
    }

    public func deleteConnection(id: String) {
        connections.removeAll(where: { $0.id == id })
        schedulePersistence()
    }

    public func removeSharedDocument(id: String) {
        sharedDocuments.removeAll(where: { $0.id == id })
        schedulePersistence()
    }

    public func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        let prevLimit = settings.searchCacheLimit
        mutate(&settings)
        UserDefaults.standard.set(settings.hasCompletedOnboarding, forKey: "rowe.hasCompletedOnboarding")
        if settings.searchCacheLimit != prevLimit {
            let limit = settings.searchCacheLimit
            Task {
                await searchIndex.setCacheLimit(limit)
                self.searchIndexStats = await searchIndex.currentStats()
            }
        }
        schedulePersistence()
    }

    public func updateSpaceName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        space.name = trimmed
        schedulePersistence()
    }

    public func updateProfile(
        authorName: String? = nil,
        email: String? = nil,
        bio: String? = nil
    ) {
        if let authorName { space.authorName = authorName }
        if let email { space.email = email }
        if let bio { space.bio = bio }
        schedulePersistence()
    }

    public func updateAvatarImageBase64(_ base64: String?) {
        if let base64, let data = Data(base64Encoded: base64), data.count > 5 * 1024 * 1024 {
            lastSyncStatusMessage = "Profile picture exceeds 5 MB limit"
            return
        }
        space.avatarImageBase64 = base64
        schedulePersistence()
        if authSession != nil {
            Task {
                do {
                    let updatedUser = try await withAuthorizedSession { sess in
                        if let base64, !base64.isEmpty {
                            return try await self.backendClient.updateAvatar(serverURL: sess.serverURL, accessToken: sess.accessToken, avatarBase64: base64)
                        } else {
                            return try await self.backendClient.deleteAvatar(serverURL: sess.serverURL, accessToken: sess.accessToken)
                        }
                    }
                    self.authSession?.user = updatedUser
                } catch {
                    self.lastSyncStatusMessage = "Avatar sync error: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Multithreaded Contextual Search, Export, Formulas, Sync

    public func performContextualSearch(query: String) {
        searchTask?.cancel()
        let context = self.currentDestination
        let maxDepth = self.settings.searchMaxDepth
        let autoDeepen = self.settings.searchAutoDeepen
        searchTask = Task {
            // 50ms debounce prevents redundant index lookups while typing rapidly.
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            let response = await searchIndex.searchContextual(
                query: query,
                context: context,
                maxDepth: maxDepth,
                autoDeepen: autoDeepen
            )
            let stats = await searchIndex.currentStats()
            guard !Task.isCancelled else { return }
            self.contextualSearchResponse = response
            self.searchIndexStats = stats
        }
    }

    public func clearSearchCache() {
        Task {
            await searchIndex.clearCache()
            self.searchIndexStats = await searchIndex.currentStats()
        }
    }

    public func rebuildSearchIndex() {
        let docs = self.documents
        let folders = self.folders
        let tags = self.tags
        let connections = self.connections
        let shared = self.sharedDocuments
        Task {
            await searchIndex.rebuildFullIndex(
                documents: docs,
                folders: folders,
                tags: tags,
                connections: connections,
                sharedDocuments: shared
            )
            self.searchIndexStats = await searchIndex.currentStats()
        }
    }

    public func performInDocumentFind(docId: String, query: String, options: SearchOptions) {
        inDocFindTask?.cancel()
        guard let doc = documents.first(where: { $0.id == docId }) else {
            inDocumentMatches = []
            return
        }
        inDocFindTask = Task {
            let matches = await searchIndex.findInDocument(doc, query: query, options: options)
            guard !Task.isCancelled else { return }
            self.inDocumentMatches = matches
        }
    }

    public func exportDocumentMarkdown(_ doc: RoweDocument) async -> String {
        await exportService.exportMarkdown(document: doc)
    }

    public func exportDocumentPlainText(_ doc: RoweDocument) async -> String {
        await exportService.exportPlainText(document: doc)
    }

    public func exportDocumentHTML(_ doc: RoweDocument) async -> String {
        await exportService.exportHTML(document: doc)
    }

    public func importMarkdownFile(content: String, filename: String) async {
        let imported = await exportService.importMarkdown(
            content,
            spaceId: space.id,
            folderId: folders.first(where: { $0.name == "Imported Notes" })?.id,
            defaultTitle: filename
        )
        documents.insert(imported, at: 0)
        persistAndReindex(imported)
        navigate(to: .document(imported.id))
    }

    /// Imports all Markdown & Craft JSON documents from one or more Craft export folders/files.
    @discardableResult
    public func importCraftExport(from urls: [URL]) async -> Int {
        var totalImported = 0
        var folderMap = Dictionary(uniqueKeysWithValues: folders.map { ($0.name, $0.id) })
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let result = await exportService.importCraftDirectory(at: url, spaceId: space.id, existingFolderNames: folderMap)
            for folder in result.newFolders {
                folders.append(folder)
                folderMap[folder.name] = folder.id
            }
            if !result.documents.isEmpty {
                documents.insert(contentsOf: result.documents, at: 0)
                totalImported += result.documents.count
            }
        }
        if totalImported > 0 {
            schedulePersistence()
            rebuildSearchIndex()
            if let first = documents.first {
                navigate(to: .document(first.id))
            }
        }
        return totalImported
    }

    public func triggerSyncNow() {
        Task {
            await syncScheduler.syncNow()
            if self.authSession != nil {
                await self.syncWithBackend()
            }
        }
    }

    /// Explicit user-initiated sync (macOS ⌘R, iOS Calendar/Settings Sync Now).
    /// Emits `manualSyncWaveId` so the converging sync-up animation ONLY plays on manual syncs.
    public func triggerManualSync() {
        guard isSignedIn else { return }
        manualSyncWaveId = UUID()
        Task { @MainActor [weak self] in
            await self?.syncWithBackend()
        }
    }

    /// Immediately flushes any pending local edits to disk and cloud (called on macOS resign/terminate/popover close).
    public func flushPendingSyncImmediately() {
        let snapshot = makeSnapshot()
        Task {
            await database.flushNow(snapshot)
        }
        guard isSignedIn, !dirtyDocumentIds.isEmpty || !pendingRemoteDeleteIds.isEmpty else { return }
        syncDebounceTask?.cancel()
        syncDebounceTask = nil
        Task { @MainActor [weak self] in
            await self?.syncWithBackend()
        }
    }

    public func handleAppBecameActive() {
        if isSignedIn {
            // Always restart SSE on foreground resume so dead background sockets reconnect immediately.
            startRealtimeSyncStream()
        }
        triggerSyncNow()
    }

    public func resetSync() {
        Task {
            await syncScheduler.resetSyncState()
        }
    }

    // MARK: - Private Helpers

    private func recomputeAllTables() {
        for doc in documents where !doc.isTrashed {
            recomputeTables(in: doc)
        }
    }

    private func recomputeTables(in doc: RoweDocument) {
        for block in doc.blocks where block.kind == .table {
            guard let tableData = block.tableData else { continue }
            let blockId = block.id
            let engine = self.formulaEngine
            formulaTasks[blockId]?.cancel()
            formulaTasks[blockId] = Task.detached(priority: .userInitiated) {
                let evaluated = engine.evaluate(table: tableData)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.evaluatedTables[blockId] = evaluated
                }
            }
        }
    }

    private func persistAndReindex(_ doc: RoweDocument, fastSync: Bool = false) {
        dirtyDocumentIds.insert(doc.id)
        dirtyDocumentVersions[doc.id, default: 0] &+= 1
        scheduleDebouncedCloudSync(delayOverride: fastSync ? 0.4 : nil)
        let snapshot = makeSnapshot()
        let docs = self.documents
        Task {
            await database.scheduleSave(snapshot)
            await searchIndex.indexDocument(doc)
            let updatedStats = await database.computeStats(for: docs)
            self.stats = updatedStats
        }
    }

    /// Coalesces rapid typing into a single delta sync (4.0s trailing debounce, 20s max-wait ceiling).
    private func scheduleDebouncedCloudSync(delayOverride: Double? = nil) {
        guard isSignedIn else { return }
        let now = Date()
        if firstDirtyAt == nil { firstDirtyAt = now }
        let elapsed = now.timeIntervalSince(firstDirtyAt ?? now)
        let delaySeconds: Double = delayOverride ?? (elapsed >= 20.0 ? 0.5 : 4.0)

        syncDebounceTask?.cancel()
        syncDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.syncWithBackend()
        }
    }

    private func schedulePersistence() {
        let snapshot = makeSnapshot()
        let docs = self.documents
        Task {
            await database.scheduleSave(snapshot)
            await syncScheduler.recordMutation()
            let updatedStats = await database.computeStats(for: docs)
            self.stats = updatedStats
        }
    }

    // MARK: - Auth & Backend Sync

    public var isSignedIn: Bool { authSession != nil }
    public var hasVaultPin: Bool { vaultEnvelope != nil }

    public func isDocumentUnlocked(_ docId: String) -> Bool {
        guard let doc = documents.first(where: { $0.id == docId }) else { return true }
        return !doc.isLocked || unlockedDocumentIds.contains(docId)
    }

    public func registerAccount(serverURL: String, email: String, password: String, displayName: String) async {
        let normalizedURL = RoweBackendClient.normalizeServerURL(serverURL.isEmpty ? Self.defaultServerURL : serverURL)
        isAuthBusy = true
        authErrorMessage = nil
        defer { isAuthBusy = false }
        do {
            let resp = try await backendClient.register(serverURL: normalizedURL, email: email, password: password, displayName: displayName)
            self.serverURL = normalizedURL
            self.authSession = AuthSession(serverURL: normalizedURL, accessToken: resp.accessToken, refreshToken: resp.refreshToken, user: resp.user)
            self.lastSyncServerTimeMs = 0
            self.space.authorName = resp.user.displayName
            self.space.email = resp.user.email
            if let remoteAvatar = resp.user.avatarBase64, !remoteAvatar.isEmpty {
                self.space.avatarImageBase64 = remoteAvatar
            } else if let localAvatar = self.space.avatarImageBase64, !localAvatar.isEmpty {
                _ = try? await backendClient.updateAvatar(serverURL: normalizedURL, accessToken: resp.accessToken, avatarBase64: localAvatar)
            }
            if let remoteVault = resp.vault {
                self.vaultEnvelope = remoteVault
            } else if let localVault = self.vaultEnvelope {
                _ = try? await backendClient.putVault(serverURL: normalizedURL, accessToken: resp.accessToken, envelope: localVault)
            }
            self.isLoginSheetPresented = false
            schedulePersistence()
            startRealtimeSyncStream()
            await syncWithBackend(forceFullPull: true)
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    public func signIn(serverURL: String, email: String, password: String) async {
        let normalizedURL = RoweBackendClient.normalizeServerURL(serverURL.isEmpty ? Self.defaultServerURL : serverURL)
        isAuthBusy = true
        authErrorMessage = nil
        defer { isAuthBusy = false }
        do {
            let resp = try await backendClient.login(serverURL: normalizedURL, email: email, password: password)
            self.serverURL = normalizedURL
            self.authSession = AuthSession(serverURL: normalizedURL, accessToken: resp.accessToken, refreshToken: resp.refreshToken, user: resp.user)
            self.lastSyncServerTimeMs = 0
            self.space.authorName = resp.user.displayName
            self.space.email = resp.user.email
            if let remoteAvatar = resp.user.avatarBase64, !remoteAvatar.isEmpty {
                self.space.avatarImageBase64 = remoteAvatar
            } else if let localAvatar = self.space.avatarImageBase64, !localAvatar.isEmpty {
                _ = try? await backendClient.updateAvatar(serverURL: normalizedURL, accessToken: resp.accessToken, avatarBase64: localAvatar)
            }
            if let remoteVault = resp.vault {
                self.vaultEnvelope = remoteVault
            } else if let localVault = self.vaultEnvelope {
                _ = try? await backendClient.putVault(serverURL: normalizedURL, accessToken: resp.accessToken, envelope: localVault)
            }
            self.isLoginSheetPresented = false
            schedulePersistence()
            startRealtimeSyncStream()
            await syncWithBackend(forceFullPull: true)
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    public func signOut() async {
        stopRealtimeSyncStream()
        if let sess = authSession {
            await backendClient.logout(serverURL: sess.serverURL, refreshToken: sess.refreshToken)
        }
        authSession = nil
        lastSyncServerTimeMs = 0
        lastSyncStatusMessage = "Signed out"
        relockAllDocuments()
        schedulePersistence()
    }

    public func startRealtimeSyncStream() {
        guard isSignedIn else { return }
        sseStreamTask?.cancel()
        fallbackPollTask?.cancel()

        sseStreamTask = Task { @MainActor [weak self] in
            var retryDelay: Double = 2.0
            while !Task.isCancelled {
                guard let self, self.isSignedIn else { return }
                do {
                    let sess = try await self.withAuthorizedSession { $0 }
                    self.isRealtimeSyncConnected = true
                    retryDelay = 2.0
                    try await self.backendClient.streamSyncEvents(
                        serverURL: sess.serverURL,
                        accessToken: sess.accessToken
                    ) { [weak self] evt in
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            if evt.type == "focus.updated" {
                                Task { await self.syncFocusStateWithBackend() }
                            } else {
                                Task { await self.syncWithBackend() }
                            }
                        }
                    }
                } catch BackendError.unauthorized {
                    self.isRealtimeSyncConnected = false
                    // Immediately refresh and reconnect with zero backoff on token expiry.
                    if (try? await self.refreshSessionSerialized()) != nil {
                        retryDelay = 2.0
                        continue
                    }
                } catch {
                    self.isRealtimeSyncConnected = false
                }
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                retryDelay = min(30.0, retryDelay * 1.8)
            }
        }

        // Gentle 30s fallback poll ONLY when SSE is disconnected (0 requests while SSE is healthy — zero DDoS).
        fallbackPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, let self, self.isSignedIn else { return }
                if !self.isRealtimeSyncConnected {
                    await self.syncWithBackend()
                }
            }
        }
    }

    public func stopRealtimeSyncStream() {
        sseStreamTask?.cancel()
        sseStreamTask = nil
        fallbackPollTask?.cancel()
        fallbackPollTask = nil
        isRealtimeSyncConnected = false
    }

    /// Coalesces concurrent 401 token refreshes behind a single in-flight task so rotating
    /// refresh tokens are never consumed twice by parallel sync/SSE/focus requests.
    private func refreshSessionSerialized() async throws -> AuthSession {
        if let existing = inFlightRefreshTask {
            return try await existing.value
        }
        guard let current = authSession else { throw BackendError.unauthorized }
        let client = self.backendClient
        let task = Task<AuthSession, Error> { @MainActor in
            let refreshed = try await client.refresh(serverURL: current.serverURL, refreshToken: current.refreshToken)
            var updated = current
            updated.accessToken = refreshed.accessToken
            updated.refreshToken = refreshed.refreshToken
            self.authSession = updated
            await self.database.scheduleSave(self.makeSnapshot())
            return updated
        }
        inFlightRefreshTask = task
        defer { inFlightRefreshTask = nil }
        return try await task.value
    }

    private func withAuthorizedSession<T>(_ operation: @Sendable (AuthSession) async throws -> T) async throws -> T {
        guard let sess = authSession else { throw BackendError.unauthorized }
        do {
            return try await operation(sess)
        } catch BackendError.unauthorized {
            let updated = try await refreshSessionSerialized()
            return try await operation(updated)
        }
    }

    public func refreshSessionAndSync() async {
        guard authSession != nil else { return }
        do {
            let profile = try await withAuthorizedSession { sess in
                try await self.backendClient.me(serverURL: sess.serverURL, accessToken: sess.accessToken)
            }
            self.space.authorName = profile.user.displayName
            self.space.email = profile.user.email
            if let remoteAvatar = profile.user.avatarBase64, !remoteAvatar.isEmpty {
                self.space.avatarImageBase64 = remoteAvatar
            }
            if let remoteVault = profile.vault {
                self.vaultEnvelope = remoteVault
            }
        } catch {
            // Best-effort profile refresh; syncWithBackend handles surfaced status if unreachable
        }
        await syncWithBackend()
    }

    private func deleteRemoteDocument(docId: String) async {
        do {
            try await withAuthorizedSession { sess in
                try await self.backendClient.deleteDocument(serverURL: sess.serverURL, accessToken: sess.accessToken, id: docId)
            }
            if pendingRemoteDeleteIds.remove(docId) != nil {
                schedulePersistence()
            }
        } catch {
            pendingRemoteDeleteIds.insert(docId)
            lastSyncStatusMessage = "Delete sync error: \(error.localizedDescription)"
        }
    }

    private func pushBackendSyncIfSignedIn() async throws {
        await syncWithBackend()
    }

    private static func makeFractionalISO8601Decoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = withFrac.date(from: str) { return d }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let d = plain.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(str)")
        }
        return dec
    }

    private static func makeFractionalISO8601Encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .custom { date, encoder in
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(fmt.string(from: date))
        }
        return enc
    }

    private func buildSyncDTOs(for ids: Set<String>, encoder: JSONEncoder) -> [SyncDocumentDTO] {
        let sealedDocs = sealedDocumentsForPersistence().filter { ids.contains($0.id) }
        return sealedDocs.map { doc in
            if doc.isLocked {
                return SyncDocumentDTO(
                    id: doc.id, spaceId: doc.spaceId, folderId: doc.folderId, title: doc.title,
                    isLocked: true, payloadJson: "", encryptedPayload: doc.encryptedPayload,
                    isStarred: doc.isStarred, isTrashed: doc.isTrashed, updatedAt: doc.updatedAt
                )
            } else {
                let payload = (try? String(data: encoder.encode(doc.blocks), encoding: .utf8)) ?? "[]"
                return SyncDocumentDTO(
                    id: doc.id, spaceId: doc.spaceId, folderId: doc.folderId, title: doc.title,
                    isLocked: false, payloadJson: payload, encryptedPayload: nil,
                    isStarred: doc.isStarred, isTrashed: doc.isTrashed, updatedAt: doc.updatedAt
                )
            }
        }
    }

    /// Coalesced delta sync: pushes only dirty docs, pulls only changes since last watermark,
    /// aligns local updatedAt with server timestamps (preventing clock-skew merge drops),
    /// preserves `(Sync Conflict)` copies instead of clobbering unpushed edits, and syncs focus state.
    public func syncWithBackend(forceFullPull: Bool = false) async {
        guard authSession != nil else { return }
        if isSyncing {
            // Never drop a concurrent task edit or SSE wakeup — queue one immediate follow-up pass.
            needsFollowUpSync = true
            return
        }
        isSyncing = true
        syncDebounceTask?.cancel()
        syncDebounceTask = nil
        defer {
            isSyncing = false
            if needsFollowUpSync {
                needsFollowUpSync = false
                Task { @MainActor [weak self] in
                    await self?.syncWithBackend()
                }
            }
        }

        do {
            // Flush any queued permanent deletes before pulling so deleted docs never resurrect.
            if !pendingRemoteDeleteIds.isEmpty {
                for delId in Array(pendingRemoteDeleteIds) {
                    try await withAuthorizedSession { sess in
                        try await self.backendClient.deleteDocument(serverURL: sess.serverURL, accessToken: sess.accessToken, id: delId)
                    }
                    pendingRemoteDeleteIds.remove(delId)
                }
            }
            let encoder = Self.makeFractionalISO8601Encoder()
            var pendingIds = (lastSyncServerTimeMs == 0) ? Set(documents.map(\.id)) : dirtyDocumentIds
            // 1s overlap window eliminates millisecond boundary skips between Go time.Now() and SQLite.
            let sinceWatermark: Int64 = forceFullPull ? 0 : max(0, lastSyncServerTimeMs - 1000)

            // Step 1: Pull delta first so tombstones and concurrent edits on another device are applied safely
            let previousWatermark = lastSyncServerTimeMs
            let tasksBeforePull = Dictionary(allTasks().map { ($0.block.id, Self.taskSyncFingerprint(for: $0.block)) }, uniquingKeysWith: { first, _ in first })
            let pulled = try await withAuthorizedSession { sess in
                try await self.backendClient.syncPull(serverURL: sess.serverURL, accessToken: sess.accessToken, sinceMs: sinceWatermark)
            }
            let deletedRemoteIds = Set(pulled.documents.filter { $0.deletedAt != nil }.map(\.id))
            pendingIds.subtract(deletedRemoteIds)
            mergeRemoteDocuments(pulled.documents, localDirtyIds: pendingIds)
            if !pulled.documents.isEmpty {
                syncPulseDirection = .received
                syncPulseId = UUID()
                rebuildSearchIndex()
                if !forceFullPull && previousWatermark > 0 {
                    let afterTasks = Dictionary(allTasks().map { ($0.block.id, Self.taskSyncFingerprint(for: $0.block)) }, uniquingKeysWith: { first, _ in first })
                    var addedOrUpdatedTaskIds: Set<String> = []
                    for (id, afterFP) in afterTasks {
                        if let beforeFP = tasksBeforePull[id] {
                            if beforeFP != afterFP {
                                addedOrUpdatedTaskIds.insert(id)
                            }
                        } else {
                            addedOrUpdatedTaskIds.insert(id)
                        }
                    }
                    let deletedTaskIds = Set(tasksBeforePull.keys).subtracting(afterTasks.keys)
                    // Play downsync wave ONLY when tasks were added, updated, or deleted (never for non-task changes)
                    if !addedOrUpdatedTaskIds.isEmpty || !deletedTaskIds.isEmpty {
                        downsyncedTaskIds = addedOrUpdatedTaskIds
                        downsyncWaveId = UUID()
                    }
                }
            }

            // Step 2: Re-merge any newly dirtied docs accumulated during pull, then snapshot versions before pushing
            pendingIds.formUnion(dirtyDocumentIds)
            pendingIds.subtract(deletedRemoteIds)
            let pushedVersions = Dictionary(uniqueKeysWithValues: pendingIds.map { ($0, dirtyDocumentVersions[$0] ?? 0) })
            let dtos = buildSyncDTOs(for: pendingIds, encoder: encoder)
            if !dtos.isEmpty {
                let pushed = try await withAuthorizedSession { sess in
                    try await self.backendClient.syncPush(serverURL: sess.serverURL, accessToken: sess.accessToken, documents: dtos)
                }
                // Align local updatedAt with authoritative server timestamps to eliminate client clock skew.
                for serverDoc in pushed.documents {
                    if let serverUpdated = serverDoc.updatedAt {
                        lastServerUpdatedAtByDoc[serverDoc.id] = serverUpdated
                        if let idx = documents.firstIndex(where: { $0.id == serverDoc.id }) {
                            documents[idx].updatedAt = serverUpdated
                        }
                    }
                }
                lastSyncServerTimeMs = max(pulled.serverTime, pushed.serverTime)
                syncPulseDirection = .sent
                syncPulseId = UUID()
            } else {
                lastSyncServerTimeMs = max(lastSyncServerTimeMs, pulled.serverTime)
            }

            let shouldCheckVault = forceFullPull || self.vaultEnvelope == nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                if shouldCheckVault,
                   let remoteVault = try? await self.withAuthorizedSession({ sess in
                       try await self.backendClient.getVault(serverURL: sess.serverURL, accessToken: sess.accessToken)
                   }) {
                    self.vaultEnvelope = remoteVault
                }
                await self.syncFocusStateWithBackend()
            }

            // Only clear dirty flags for docs whose version did not advance while push was in flight
            for id in pendingIds {
                if (dirtyDocumentVersions[id] ?? 0) == pushedVersions[id] {
                    dirtyDocumentIds.remove(id)
                } else {
                    needsFollowUpSync = true
                }
            }
            dirtyDocumentIds.subtract(deletedRemoteIds)
            firstDirtyAt = dirtyDocumentIds.isEmpty ? nil : Date()
            consecutiveSyncFailures = 0
            let now = Date()
            lastSuccessfulSyncAt = now
            lastSyncStatusMessage = "Synced at \(now.formatted(date: .omitted, time: .shortened))"
            await database.scheduleSave(makeSnapshot())
        } catch {
            consecutiveSyncFailures += 1
            let backoffSecs = min(120.0, 5.0 * pow(3.0, Double(consecutiveSyncFailures - 1)))
            lastSyncStatusMessage = "Offline · retrying in \(Int(backoffSecs))s"
            syncDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(backoffSecs * 1_000_000_000))
                guard !Task.isCancelled, let self, self.isSignedIn, !self.dirtyDocumentIds.isEmpty else { return }
                await self.syncWithBackend()
            }
        }
    }

    private static func taskSyncFingerprint(for block: Block) -> String {
        let state = block.task?.state.rawValue ?? 0
        let sched = block.task?.scheduleDate.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
        let repeatFreq = block.task?.repeatRule?.frequency.rawValue ?? "none"
        let imgCount = block.task?.attachedImagesBase64.count ?? 0
        let notes = block.task?.notes ?? ""
        return "\(block.content)|\(state)|\(sched)|\(repeatFreq)|\(imgCount)|\(notes)"
    }

    private func mergeRemoteDocuments(_ remoteDocs: [SyncDocumentDTO], localDirtyIds: Set<String>) {
        let decoder = Self.makeFractionalISO8601Decoder()
        for r in remoteDocs {
            // Respect server tombstones and queued local permanent deletes so deleted docs never resurrect.
            if r.deletedAt != nil || pendingRemoteDeleteIds.contains(r.id) {
                documents.removeAll(where: { $0.id == r.id })
                dirtyDocumentIds.remove(r.id)
                if case .document(let currentId) = currentDestination, currentId == r.id {
                    navigate(to: .allDocs)
                }
                continue
            }
            if let idx = documents.firstIndex(where: { $0.id == r.id }) {
                let remoteUpdated = r.updatedAt ?? Date.distantPast
                let localDoc = documents[idx]
                let isLocalDirty = localDirtyIds.contains(r.id)
                if isLocalDirty, let knownServerTs = lastServerUpdatedAtByDoc[r.id], knownServerTs == remoteUpdated {
                    continue
                }
                if let rTs = r.updatedAt {
                    lastServerUpdatedAtByDoc[r.id] = rTs
                }

                var decodedRemoteBlocks: [Block]? = nil
                if !r.isLocked, let raw = r.payloadJson?.data(using: .utf8),
                   let decoded = try? decoder.decode([Block].self, from: raw) {
                    decodedRemoteBlocks = decoded
                }

                let isTaskContainer = localDoc.title == "Tasks Inbox" || r.title == "Tasks Inbox"
                    || localDoc.blocks.contains(where: \.isTaskOrTombstone)
                    || (decodedRemoteBlocks?.contains(where: \.isTaskOrTombstone) ?? false)

                if isTaskContainer && !r.isLocked, let remoteBlocks = decodedRemoteBlocks {
                    // True per-task CRDT merge: NEVER fork Tasks Inbox into (Sync Conflict) and NEVER drop tasks
                    // created or edited on either device. Each block resolves by newest updatedAt + tombstones.
                    let merged = Self.mergeTaskBlocksCRDT(local: localDoc.blocks, remote: remoteBlocks, documentId: localDoc.id)
                    documents[idx].blocks = merged
                    documents[idx].encryptedPayload = nil
                    documents[idx].title = r.title.isEmpty ? localDoc.title : r.title
                    documents[idx].folderId = (r.folderId?.isEmpty == false) ? r.folderId : localDoc.folderId
                    documents[idx].isStarred = r.isStarred || localDoc.isStarred
                    documents[idx].isTrashed = r.isTrashed
                    documents[idx].updatedAt = max(localDoc.updatedAt, remoteUpdated)
                    if merged != remoteBlocks {
                        // Local device contributed newer/additional tasks or tombstones — push merged union back.
                        dirtyDocumentIds.insert(localDoc.id)
                        dirtyDocumentVersions[localDoc.id, default: 0] &+= 1
                    }
                    continue
                }

                let bothEdited = isLocalDirty && remoteUpdated > localDoc.updatedAt
                if bothEdited {
                    let conflictDoc = RoweDocument(
                        id: UUID().uuidString,
                        spaceId: localDoc.spaceId,
                        folderId: localDoc.folderId,
                        title: "\(r.title.isEmpty ? localDoc.displayTitle : r.title) (Sync Conflict)",
                        blocks: decodedRemoteBlocks ?? [],
                        style: localDoc.style,
                        isLocked: r.isLocked,
                        encryptedPayload: r.isLocked ? r.encryptedPayload : nil,
                        authorName: space.authorName,
                        updatedAt: remoteUpdated
                    )
                    documents.insert(conflictDoc, at: 0)
                } else if !isLocalDirty || remoteUpdated > localDoc.updatedAt {
                    documents[idx].title = r.title
                    documents[idx].folderId = (r.folderId?.isEmpty == false) ? r.folderId : nil
                    documents[idx].isLocked = r.isLocked
                    documents[idx].isStarred = r.isStarred
                    documents[idx].isTrashed = r.isTrashed
                    documents[idx].updatedAt = remoteUpdated
                    if r.isLocked {
                        documents[idx].encryptedPayload = r.encryptedPayload
                        if !unlockedDocumentIds.contains(r.id) {
                            documents[idx].blocks = []
                        }
                    } else if let decoded = decodedRemoteBlocks {
                        documents[idx].blocks = decoded
                        documents[idx].encryptedPayload = nil
                    }
                }
            } else {
                var blocks: [Block] = []
                if !r.isLocked, let raw = r.payloadJson?.data(using: .utf8),
                   let decoded = try? decoder.decode([Block].self, from: raw) {
                    blocks = decoded
                }
                let newDoc = RoweDocument(
                    id: r.id,
                    spaceId: r.spaceId.isEmpty ? space.id : r.spaceId,
                    folderId: (r.folderId?.isEmpty == false) ? r.folderId : nil,
                    title: r.title,
                    blocks: blocks,
                    isStarred: r.isStarred,
                    isTrashed: r.isTrashed,
                    isLocked: r.isLocked,
                    encryptedPayload: r.isLocked ? r.encryptedPayload : nil,
                    authorName: space.authorName,
                    updatedAt: r.updatedAt ?? Date()
                )
                documents.append(newDoc)
            }
        }
        deduplicateInboxAndSeedDocuments()
    }

    /// Deterministic per-block CRDT merge for task containers:
    /// - Resolves same-ID blocks by newest `updatedAt` (with deterministic tombstone/state tie-breaker).
    /// - Preserves unique blocks created on either device so offline tasks are never overwritten.
    /// - Garbage-collects tombstones older than 30 days.
    private static func mergeTaskBlocksCRDT(local: [Block], remote: [Block], documentId: String) -> [Block] {
        var byId: [String: Block] = [:]
        var orderedIds: [String] = []

        func pickWinner(_ a: Block, _ b: Block) -> Block {
            let delta = a.updatedAt.timeIntervalSince(b.updatedAt)
            if abs(delta) > 0.001 {
                return delta > 0 ? a : b
            }
            if (a.deletedAt != nil) != (b.deletedAt != nil) {
                return a.deletedAt != nil ? a : b
            }
            let aState = a.task?.state.rawValue ?? 0
            let bState = b.task?.state.rawValue ?? 0
            if aState != bState {
                return aState > bState ? a : b
            }
            return a.content >= b.content ? a : b
        }

        for var blk in local {
            blk.documentId = documentId
            if let existing = byId[blk.id] {
                byId[blk.id] = pickWinner(existing, blk)
            } else {
                byId[blk.id] = blk
                orderedIds.append(blk.id)
            }
        }
        for var blk in remote {
            blk.documentId = documentId
            if let existing = byId[blk.id] {
                byId[blk.id] = pickWinner(existing, blk)
            } else {
                byId[blk.id] = blk
                orderedIds.append(blk.id)
            }
        }

        let tombstoneCutoff = Date().addingTimeInterval(-30 * 86400)
        return orderedIds.compactMap { id in
            guard let blk = byId[id] else { return nil }
            if let del = blk.deletedAt, del < tombstoneCutoff { return nil }
            return blk
        }
    }

    /// Merges duplicate "Tasks Inbox" AND any legacy "Tasks Inbox (Sync Conflict)" documents via CRDT
    /// so tasks never double across devices.
    private func deduplicateInboxAndSeedDocuments() {
        let inboxIndices = documents.indices.filter {
            !documents[$0].isTrashed && (documents[$0].title == "Tasks Inbox" || documents[$0].title.hasPrefix("Tasks Inbox (Sync Conflict)"))
        }
        if !inboxIndices.isEmpty {
            let canonicalIdx = inboxIndices.first(where: { documents[$0].id == "rowe-seed-inbox" })
                ?? inboxIndices.first(where: { documents[$0].title == "Tasks Inbox" })
                ?? inboxIndices[0]
            let canonicalId = documents[canonicalIdx].id
            var mergedBlocks = documents[canonicalIdx].blocks
            var duplicateIdsToRemove: [String] = []

            for idx in inboxIndices where idx != canonicalIdx {
                mergedBlocks = Self.mergeTaskBlocksCRDT(local: mergedBlocks, remote: documents[idx].blocks, documentId: canonicalId)
                duplicateIdsToRemove.append(documents[idx].id)
            }

            let deduped = deduplicatedTaskBlocks(mergedBlocks, documentId: canonicalId)
            let changed = !duplicateIdsToRemove.isEmpty || deduped != documents[canonicalIdx].blocks
            if changed {
                documents[canonicalIdx].title = "Tasks Inbox"
                documents[canonicalIdx].blocks = deduped
                documents[canonicalIdx].updatedAt = Date()
                if !duplicateIdsToRemove.isEmpty {
                    let removeSet = Set(duplicateIdsToRemove)
                    documents.removeAll(where: { removeSet.contains($0.id) })
                    dirtyDocumentIds.insert(canonicalId)
                    dirtyDocumentVersions[canonicalId, default: 0] &+= 1
                    if authSession != nil {
                        for dupId in duplicateIdsToRemove {
                            pendingRemoteDeleteIds.insert(dupId)
                            Task { await deleteRemoteDocument(docId: dupId) }
                        }
                    }
                }
            }
        }

        // Also collapse duplicate fresh-install seed docs created before deterministic IDs
        let seedMap: [(title: String, canonicalId: String)] = [
            ("Product Launch Tracker", "rowe-seed-tracker"),
            ("Quick Scratchpad", "rowe-seed-scratch"),
            ("Attention Mechanisms", "rowe-seed-attention")
        ]
        for entry in seedMap {
            let matching = documents.filter { $0.title == entry.title && !$0.isTrashed }
            guard matching.count > 1 else { continue }
            let keeper = matching.first(where: { $0.id == entry.canonicalId })
                ?? matching.max(by: { $0.updatedAt < $1.updatedAt })
                ?? matching[0]
            let extras = matching.filter { $0.id != keeper.id }
            let extraIds = Set(extras.map(\.id))
            documents.removeAll(where: { extraIds.contains($0.id) })
            if authSession != nil {
                for extraId in extraIds {
                    Task { await deleteRemoteDocument(docId: extraId) }
                }
            }
        }
    }

    private func deduplicatedTaskBlocks(_ blocks: [Block], documentId: String) -> [Block] {
        var result: [Block] = []
        var seenTaskKeyToIndex: [String: Int] = [:]
        var seenBlockIds: Set<String> = []
        let cal = Calendar.current

        for var block in blocks {
            block.documentId = documentId
            if seenBlockIds.contains(block.id) { continue }
            seenBlockIds.insert(block.id)

            if block.isTask {
                let normalizedTitle = block.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let dayKey: String
                if let sched = block.task?.scheduleDate {
                    let comps = cal.dateComponents([.year, .month, .day], from: sched)
                    dayKey = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
                } else {
                    dayKey = "unscheduled"
                }
                let key = "\(normalizedTitle)|\(dayKey)"
                if let existingIdx = seenTaskKeyToIndex[key] {
                    // Keep whichever copy is more recently updated (or completed/canceled over pending)
                    let existing = result[existingIdx]
                    let existingDone = (existing.task?.state ?? .pending) != .pending
                    let candidateDone = (block.task?.state ?? .pending) != .pending
                    if (candidateDone && !existingDone) || block.updatedAt > existing.updatedAt {
                        result[existingIdx] = block
                    }
                    continue
                }
                seenTaskKeyToIndex[key] = result.count
            }
            result.append(block)
        }
        return result
    }

    // MARK: - Zero-Knowledge PIN-Locked Notes

    public func requestToggleLock(for docId: String) {
        guard let doc = documents.first(where: { $0.id == docId }) else { return }
        if !hasVaultPin {
            pinPromptRequest = .setupPin(lockDocumentId: docId)
            return
        }
        if doc.isLocked {
            if unlockedDocumentIds.contains(docId) {
                sealLockedDocument(docId)
            } else {
                pinPromptRequest = .unlockDocument(docId: docId)
            }
        } else {
            if unlockedVaultKey != nil {
                lockDocument(docId)
            } else {
                pinPromptRequest = .unlockDocument(docId: docId)
            }
        }
    }

    public func setupVaultPin(_ pin: String, pinLength: Int, thenLockDocId: String?) async throws {
        let (key, envelope) = try NoteCryptoService.createVault(pin: pin, pinLength: pinLength)
        self.unlockedVaultKey = key
        self.vaultEnvelope = envelope
        self.failedPinAttempts = 0
        self.pinLockoutUntil = nil

        if let docId = thenLockDocId {
            lockDocument(docId)
        }
        schedulePersistence()

        if let sess = authSession {
            _ = try? await backendClient.putVault(serverURL: sess.serverURL, accessToken: sess.accessToken, envelope: envelope)
            await syncWithBackend()
        }
    }

    public func changeVaultPin(currentPin: String, newPin: String, pinLength: Int) async throws {
        guard let env = vaultEnvelope else { throw NoteCryptoError.missingVaultKey }
        let key = try NoteCryptoService.unwrapVaultKey(pin: currentPin, envelope: env)
        let newEnv = try NoteCryptoService.wrapVaultKey(key, withPin: newPin, pinLength: pinLength)
        self.unlockedVaultKey = key
        self.vaultEnvelope = newEnv
        schedulePersistence()
        if let sess = authSession {
            _ = try? await backendClient.putVault(serverURL: sess.serverURL, accessToken: sess.accessToken, envelope: newEnv)
        }
    }

    public func verifyPinAndUnlock(docId: String, pin: String) throws {
        if let until = pinLockoutUntil, until > Date() {
            throw NoteCryptoError.invalidPin
        }
        guard let env = vaultEnvelope else { throw NoteCryptoError.missingVaultKey }
        do {
            let key = try NoteCryptoService.unwrapVaultKey(pin: pin, envelope: env)
            self.unlockedVaultKey = key
            self.failedPinAttempts = 0
            self.pinLockoutUntil = nil

            guard let idx = documents.firstIndex(where: { $0.id == docId }) else { return }
            if documents[idx].isLocked {
                if let cipher = documents[idx].encryptedPayload, !cipher.isEmpty {
                    let decrypted = try NoteCryptoService.decryptBlocks(from: cipher, with: key)
                    documents[idx].blocks = decrypted.isEmpty ? [Block(documentId: docId, content: "")] : decrypted
                }
                unlockedDocumentIds.insert(docId)
            } else {
                lockDocument(docId)
            }
        } catch {
            failedPinAttempts += 1
            if failedPinAttempts >= 5 {
                pinLockoutUntil = Date().addingTimeInterval(15)
            }
            throw NoteCryptoError.invalidPin
        }
    }

    public func lockDocument(_ docId: String) {
        guard let key = unlockedVaultKey,
              let idx = documents.firstIndex(where: { $0.id == docId }) else { return }
        guard let cipher = try? NoteCryptoService.encryptBlocks(documents[idx].blocks, with: key) else { return }
        documents[idx].encryptedPayload = cipher
        documents[idx].isLocked = true
        documents[idx].blocks = []
        documents[idx].updatedAt = Date()
        unlockedDocumentIds.remove(docId)
        persistAndReindex(documents[idx])
    }

    public func sealLockedDocument(_ docId: String) {
        guard let key = unlockedVaultKey,
              let idx = documents.firstIndex(where: { $0.id == docId }),
              documents[idx].isLocked else { return }
        if let cipher = try? NoteCryptoService.encryptBlocks(documents[idx].blocks, with: key) {
            documents[idx].encryptedPayload = cipher
        }
        documents[idx].blocks = []
        documents[idx].updatedAt = Date()
        unlockedDocumentIds.remove(docId)
        persistAndReindex(documents[idx])
    }

    public func removeLockPermanently(docId: String) {
        guard let idx = documents.firstIndex(where: { $0.id == docId }),
              documents[idx].isLocked,
              unlockedDocumentIds.contains(docId) else { return }
        documents[idx].isLocked = false
        documents[idx].encryptedPayload = nil
        documents[idx].updatedAt = Date()
        unlockedDocumentIds.remove(docId)
        persistAndReindex(documents[idx])
    }

    public func relockAllDocuments() {
        for id in Array(unlockedDocumentIds) {
            sealLockedDocument(id)
        }
        unlockedDocumentIds.removeAll()
        unlockedVaultKey = nil
    }

    /// Guarantees locked documents NEVER write plaintext blocks to disk or sync payloads, even while unlocked in RAM,
    /// and ensures completely blank untitled notes are never persisted or synced.
    private func sealedDocumentsForPersistence() -> [RoweDocument] {
        documents.compactMap { doc in
            if isDocumentEmpty(doc) { return nil }
            guard doc.isLocked else { return doc }
            var copy = doc
            if unlockedDocumentIds.contains(doc.id), let key = unlockedVaultKey,
               let freshCipher = try? NoteCryptoService.encryptBlocks(doc.blocks, with: key) {
                copy.encryptedPayload = freshCipher
            }
            copy.blocks = []
            return copy
        }
    }

    // MARK: - Adaptive Focus & Behavioral Nudge Engine (Zero Blocking)

    /// Returns ONLY unlocked, non-trashed pending tasks — enforcing the Zero-Knowledge firewall.
    public func unlockedNudgeCandidateTasks() -> [NudgeCandidateTask] {
        var candidates: [NudgeCandidateTask] = []
        for doc in documents where !doc.isLocked && doc.encryptedPayload == nil && !doc.isTrashed {
            func collect(_ blocks: [Block]) {
                for b in blocks {
                    if b.isTask {
                        let item = ResolvedTaskItem(
                            block: b,
                            documentId: doc.id,
                            documentTitle: doc.displayTitle,
                            isInbox: b.task?.isInbox ?? (doc.title == "Tasks Inbox")
                        )
                        if let candidate = NudgeCandidateTask(from: item, in: doc) {
                            candidates.append(candidate)
                        }
                    }
                    collect(b.subblocks)
                }
            }
            collect(doc.blocks)
        }
        return candidates
    }

    public func recordFocusInterval(_ interval: UsageInterval) {
        guard interval.durationSeconds >= 5 else { return }
        focusBehavior.intervals.append(interval)
        let cutoff = Date().addingTimeInterval(-45 * 86400)
        focusBehavior.intervals = focusBehavior.intervals.filter { $0.endUTC >= cutoff }
        focusBehavior.updatedAt = Date()
        schedulePersistence()
        scheduleDebouncedFocusSync()
    }

    @discardableResult
    public func evaluateFocusNudge(
        for canonicalTarget: String,
        at now: Date = Date(),
        bypassColdStartForPreview: Bool = false
    ) -> FocusSuggestion? {
        let candidates = unlockedNudgeCandidateTasks()
        let suggestion = focusEngine.evaluateNudge(
            target: canonicalTarget,
            candidates: candidates,
            state: focusBehavior,
            now: now,
            bypassColdStartForPreview: bypassColdStartForPreview
        )
        if let suggestion {
            activeFocusSuggestion = suggestion
        }
        return suggestion
    }

    public func recordFocusOutcome(_ outcome: NudgeOutcome, for suggestion: FocusSuggestion, at now: Date = Date()) {
        focusEngine.recordOutcome(outcome, for: suggestion, deviceId: deviceId, into: &focusBehavior, now: now)
        if activeFocusSuggestion?.id == suggestion.id {
            activeFocusSuggestion = nil
        }
        schedulePersistence()
        scheduleDebouncedFocusSync(delaySeconds: 1.0)
    }

    public func unmuteFocusSlot(storageKey: String) {
        guard var rec = focusBehavior.receptivityBySlot[storageKey] else { return }
        rec.alpha = 2.0
        rec.beta = 2.0
        rec.lastSilencedUTC = nil
        rec.lastUpdatedUTC = Date()
        focusBehavior.receptivityBySlot[storageKey] = rec
        focusBehavior.updatedAt = Date()
        schedulePersistence()
        scheduleDebouncedFocusSync(delaySeconds: 1.0)
    }

    public func toggleFocusEnabled(_ enabled: Bool) {
        focusBehavior.isEnabled = enabled
        focusBehavior.updatedAt = Date()
        if !enabled { activeFocusSuggestion = nil }
        schedulePersistence()
        scheduleDebouncedFocusSync(delaySeconds: 1.0)
    }

    public func addFocusAllowlistedDomain(_ raw: String) {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .split(separator: "/").first.map(String.init) ?? ""
        guard !clean.isEmpty, !focusBehavior.allowlistedDomains.contains(clean) else { return }
        focusBehavior.allowlistedDomains.append(clean)
        focusBehavior.allowlistedDomains.sort()
        focusBehavior.updatedAt = Date()
        schedulePersistence()
        scheduleDebouncedFocusSync(delaySeconds: 1.5)
    }

    public func removeFocusAllowlistedDomain(_ domain: String) {
        focusBehavior.allowlistedDomains.removeAll { $0 == domain }
        focusBehavior.updatedAt = Date()
        schedulePersistence()
        scheduleDebouncedFocusSync(delaySeconds: 1.5)
    }

    public func addCustomDistractionTarget(_ raw: String) {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty, !focusBehavior.customDistractionTargets.contains(clean) else { return }
        focusBehavior.customDistractionTargets.append(clean)
        focusBehavior.customDistractionTargets.sort()
        focusBehavior.updatedAt = Date()
        schedulePersistence()
        scheduleDebouncedFocusSync(delaySeconds: 1.5)
    }

    public func removeCustomDistractionTarget(_ target: String) {
        focusBehavior.customDistractionTargets.removeAll { $0 == target }
        focusBehavior.updatedAt = Date()
        schedulePersistence()
        scheduleDebouncedFocusSync(delaySeconds: 1.5)
    }

    public func circadianFocusMinutes(daysBack: Int = 7) -> [Double] {
        focusEngine.circadianMinutesBySlot(in: focusBehavior, daysBack: daysBack)
    }

    public func mergedFocusSessions(for target: String) -> [UsageInterval] {
        focusEngine.mergedSessions(for: target, from: focusBehavior.intervals)
    }

    /// Generates a realistic live preview suggestion using an actual unlocked pending task (or a calm fallback).
    public func makePreviewFocusSuggestion() -> FocusSuggestion {
        let candidates = unlockedNudgeCandidateTasks()
        if let real = focusEngine.evaluateNudge(
            target: "canon:instagram",
            candidates: candidates,
            state: focusBehavior,
            now: Date(),
            bypassColdStartForPreview: true
        ) {
            return real
        }
        let sampleTask = NudgeCandidateTask(
            id: "preview-sample",
            documentId: documents.first?.id ?? "inbox",
            title: "Reply to project review notes",
            scheduleDate: Date()
        )
        let slotKey = FocusSlotKey.from(date: Date(), tzOffsetMinutes: TimeZone.current.secondsFromGMT() / 60, target: "canon:instagram")
        return FocusSuggestion(
            canonicalTarget: "canon:instagram",
            displayAppName: "Instagram",
            iconName: "camera.aperture",
            headline: "Usually afternoons on Instagram run ~1h 30m",
            detailLine: "Knock out \"Reply to project review notes\" (~10m) first, then scroll freely?",
            task: sampleTask,
            estimatedMinutes: 10,
            predictedScrollMinutes: 90,
            slotKey: slotKey,
            isPersonalized: true
        )
    }

    private func estimateAndCacheDuration(for candidate: NudgeCandidateTask) async {
        let mins = await focusEstimator.estimateMinutes(for: candidate)
        var stat = focusBehavior.taskStats[candidate.id] ?? TaskNudgeStats(taskId: candidate.id, estimatedMinutes: mins, lastEditedAt: candidate.updatedAt)
        stat.estimatedMinutes = mins
        focusBehavior.taskStats[candidate.id] = stat
        schedulePersistence()
    }

    private func scheduleDebouncedFocusSync(delaySeconds: Double = 5.0) {
        guard isSignedIn else { return }
        focusSyncDebounceTask?.cancel()
        focusSyncDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.syncFocusStateWithBackend()
        }
    }

    public func syncFocusStateWithBackend() async {
        guard isSignedIn else { return }
        do {
            if let remote = try await withAuthorizedSession({ sess in
                try await self.backendClient.getFocusState(serverURL: sess.serverURL, accessToken: sess.accessToken)
            }) {
                self.focusBehavior.merge(with: remote)
            }
            _ = try await withAuthorizedSession { sess in
                try await self.backendClient.putFocusState(serverURL: sess.serverURL, accessToken: sess.accessToken, state: self.focusBehavior)
            }
            await database.scheduleSave(makeSnapshot())
        } catch {
            // Focus sync is best-effort; never interrupt document editing or block apps.
        }
    }

    private func makeSnapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            space: space,
            folders: folders,
            tags: tags,
            sidebarSections: sidebarSections,
            documents: sealedDocumentsForPersistence(),
            sharedDocuments: sharedDocuments,
            connections: connections,
            settings: settings,
            vaultEnvelope: vaultEnvelope,
            authSession: authSession,
            serverURL: serverURL,
            lastSyncServerTimeMs: lastSyncServerTimeMs,
            dirtyDocumentIds: Array(dirtyDocumentIds),
            pendingRemoteDeleteIds: Array(pendingRemoteDeleteIds),
            focusBehavior: focusBehavior
        )
    }

    private func cloneBlock(_ block: Block, newDocumentId: String) -> Block {
        var copy = block
        copy.id = UUID().uuidString
        copy.documentId = newDocumentId
        copy.subblocks = block.subblocks.map { cloneBlock($0, newDocumentId: newDocumentId) }
        return copy
    }

    private static func mutateBlockRecursive(in blocks: inout [Block], id: String, _ mutate: (inout Block) -> Void) -> Bool {
        for idx in blocks.indices {
            if blocks[idx].id == id {
                mutate(&blocks[idx])
                blocks[idx].updatedAt = Date()
                return true
            }
            if mutateBlockRecursive(in: &blocks[idx].subblocks, id: id, mutate) {
                return true
            }
        }
        return false
    }

    private static func tombstoneOrRemoveBlockRecursive(in blocks: inout [Block], id: String, now: Date, deletedTask: inout Bool) -> Bool {
        if let idx = blocks.firstIndex(where: { $0.id == id }) {
            if blocks[idx].isTaskOrTombstone {
                blocks[idx].deletedAt = now
                blocks[idx].updatedAt = now
                deletedTask = true
            } else {
                blocks.remove(at: idx)
            }
            return true
        }
        for idx in blocks.indices {
            if tombstoneOrRemoveBlockRecursive(in: &blocks[idx].subblocks, id: id, now: now, deletedTask: &deletedTask) {
                return true
            }
        }
        return false
    }
}
