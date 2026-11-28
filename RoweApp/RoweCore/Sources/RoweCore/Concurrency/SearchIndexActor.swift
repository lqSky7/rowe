import Foundation

public struct SearchOptions: Hashable, Sendable {
    public var useRegex: Bool
    public var caseInsensitive: Bool
    public var diacriticsInsensitive: Bool

    public init(useRegex: Bool = false, caseInsensitive: Bool = true, diacriticsInsensitive: Bool = true) {
        self.useRegex = useRegex
        self.caseInsensitive = caseInsensitive
        self.diacriticsInsensitive = diacriticsInsensitive
    }
}

public enum GlobalSearchHitKind: Hashable, Sendable {
    case document(documentId: String)
    case block(documentId: String, blockId: String)
    case task(documentId: String, blockId: String)
    case folder(folderId: String)
    case tag(name: String)
    case connection(connectionId: String)
    case sharedDocument(sharedId: String)
    case settingsSection(sectionId: String)
}

public struct GlobalSearchHit: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: GlobalSearchHitKind
    public var title: String
    public var subtitle: String
    public var depthTier: SearchMaxDepth
    public var scopeLabel: String
    public var score: Int

    public init(
        id: String,
        kind: GlobalSearchHitKind,
        title: String,
        subtitle: String,
        depthTier: SearchMaxDepth,
        scopeLabel: String,
        score: Int
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.depthTier = depthTier
        self.scopeLabel = scopeLabel
        self.score = score
    }
}

public struct ContextualSearchResponse: Hashable, Sendable {
    public var hits: [GlobalSearchHit]
    public var reachedDepth: SearchMaxDepth
    public var servedFromCache: Bool

    public init(hits: [GlobalSearchHit] = [], reachedDepth: SearchMaxDepth = .currentView, servedFromCache: Bool = false) {
        self.hits = hits
        self.reachedDepth = reachedDepth
        self.servedFromCache = servedFromCache
    }
}

public struct SearchIndexStats: Hashable, Sendable {
    public var indexedRecordCount: Int
    public var uniqueTokenCount: Int
    public var cachedQueryCount: Int
    public var cacheLimit: Int

    public init(indexedRecordCount: Int = 0, uniqueTokenCount: Int = 0, cachedQueryCount: Int = 0, cacheLimit: Int = 128) {
        self.indexedRecordCount = indexedRecordCount
        self.uniqueTokenCount = uniqueTokenCount
        self.cachedQueryCount = cachedQueryCount
        self.cacheLimit = cacheLimit
    }
}

public struct InDocumentMatch: Identifiable, Hashable, Sendable {
    public var id: String { "\(blockId)::\(utf16Location)" }
    public var blockId: String
    public var utf16Location: Int
    public var utf16Length: Int
    public var preview: String

    public init(blockId: String, utf16Location: Int, utf16Length: Int, preview: String) {
        self.blockId = blockId
        self.utf16Location = utf16Location
        self.utf16Length = utf16Length
        self.preview = preview
    }
}

/// Off-main-thread inverted-token search engine with bounded LRU query caching
/// and contextual tiered deepening (Current View -> Related -> Everything).
public actor SearchIndexActor {
    private struct IndexedRecord: Sendable {
        let id: String
        let kind: GlobalSearchHitKind
        let title: String
        let subtitle: String
        let foldedSearchText: String
        let tokens: Set<String>
        let ownerDocumentId: String?
        let folderId: String?
        let tags: Set<String>
        let isDeepBlockBody: Bool
    }

    private struct CacheKey: Hashable {
        let normalizedQuery: String
        let context: WorkspaceDestination
        let maxDepth: SearchMaxDepth
        let autoDeepen: Bool
    }

    private var records: [String: IndexedRecord] = [:]
    private var invertedIndex: [String: Set<String>] = [:]
    private var queryCache: [CacheKey: ContextualSearchResponse] = [:]
    private var cacheOrder: [CacheKey] = []
    private var cacheLimit: Int = 128

    public init() {}

    public func setCacheLimit(_ limit: Int) {
        cacheLimit = max(0, limit)
        trimCacheIfNeeded()
    }

    public func clearCache() {
        queryCache.removeAll()
        cacheOrder.removeAll()
    }

    public func currentStats() -> SearchIndexStats {
        SearchIndexStats(
            indexedRecordCount: records.count,
            uniqueTokenCount: invertedIndex.count,
            cachedQueryCount: queryCache.count,
            cacheLimit: cacheLimit
        )
    }

    public func rebuildFullIndex(
        documents: [RoweDocument],
        folders: [Folder],
        tags: [TagItem],
        connections: [ConnectionItem],
        sharedDocuments: [SharedDocumentItem]
    ) {
        records.removeAll(keepingCapacity: true)
        invertedIndex.removeAll(keepingCapacity: true)
        clearCache()

        for folder in folders {
            insertRecord(makeFolderRecord(folder))
        }
        for tag in tags {
            insertRecord(makeTagRecord(tag))
        }
        for conn in connections {
            insertRecord(makeConnectionRecord(conn))
        }
        for shared in sharedDocuments {
            insertRecord(makeSharedRecord(shared))
        }
        for rec in makeSettingsRecords() {
            insertRecord(rec)
        }
        for doc in documents where !doc.isTrashed {
            for rec in makeDocumentRecords(doc) {
                insertRecord(rec)
            }
        }
    }

    /// Incrementally updates only the records belonging to a single document.
    public func indexDocument(_ doc: RoweDocument) {
        let toRemove = records.values.filter { $0.ownerDocumentId == doc.id }.map(\.id)
        for id in toRemove {
            removeRecord(id: id)
        }
        if !doc.isTrashed {
            for rec in makeDocumentRecords(doc) {
                insertRecord(rec)
            }
        }
        clearCache()
    }

    /// Executes contextual tiered search:
    /// 1) Current View scope first.
    /// 2) If empty (and `autoDeepen` + `maxDepth` allow), widens to Related metadata scope.
    /// 3) If still empty (and `maxDepth == .everything`), searches the full workspace index.
    public func searchContextual(
        query: String,
        context: WorkspaceDestination,
        maxDepth: SearchMaxDepth,
        autoDeepen: Bool,
        limit: Int = 30
    ) -> ContextualSearchResponse {
        let normalized = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalized.isEmpty else {
            return ContextualSearchResponse(hits: [], reachedDepth: .currentView, servedFromCache: false)
        }

        let cacheKey = CacheKey(
            normalizedQuery: normalized,
            context: context,
            maxDepth: maxDepth,
            autoDeepen: autoDeepen
        )

        if cacheLimit > 0, let cached = queryCache[cacheKey] {
            touchCacheKey(cacheKey)
            return ContextualSearchResponse(hits: cached.hits, reachedDepth: cached.reachedDepth, servedFromCache: true)
        }

        let candidateIds = candidateRecordIDs(for: normalized)
        let queryTerms = tokenize(normalized)

        var collected: [GlobalSearchHit] = []
        var seenIds = Set<String>()
        var reachedDepth: SearchMaxDepth = .currentView

        func runTier(_ tier: SearchMaxDepth) {
            reachedDepth = tier
            for recId in candidateIds where !seenIds.contains(recId) {
                guard let rec = records[recId] else { continue }
                guard matchesTier(rec, tier: tier, context: context) else { continue }
                guard let matchScore = scoreMatch(rec, fullQuery: normalized, terms: queryTerms, tier: tier) else { continue }
                seenIds.insert(recId)
                collected.append(GlobalSearchHit(
                    id: rec.id,
                    kind: rec.kind,
                    title: rec.title,
                    subtitle: rec.subtitle,
                    depthTier: tier,
                    scopeLabel: scopeLabel(for: rec, tier: tier),
                    score: matchScore
                ))
            }
        }

        // Tier 1: Current View
        runTier(.currentView)

        // Tier 2: Related Scope (only if needed or auto-deepening)
        if maxDepth >= .relatedScope && (collected.isEmpty || (autoDeepen && collected.count < 5)) {
            runTier(.relatedScope)
        }

        // Tier 3: Everything (deep block bodies, tables, collections across all docs)
        if maxDepth >= .everything && (collected.isEmpty || (autoDeepen && collected.count < 8)) {
            runTier(.everything)
        }

        collected.sort { lhs, rhs in
            if lhs.depthTier != rhs.depthTier { return lhs.depthTier < rhs.depthTier }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        let response = ContextualSearchResponse(
            hits: Array(collected.prefix(limit)),
            reachedDepth: reachedDepth,
            servedFromCache: false
        )

        if cacheLimit > 0 {
            storeInCache(cacheKey, response: response)
        }
        return response
    }

    public func findInDocument(_ document: RoweDocument, query: String, options: SearchOptions) -> [InDocumentMatch] {
        guard !query.isEmpty else { return [] }
        var matches: [InDocumentMatch] = []

        func scanBlock(_ block: Block) {
            let text = block.content
            if !text.isEmpty {
                let nsText = text as NSString
                if options.useRegex {
                    var regexOpts: NSRegularExpression.Options = []
                    if options.caseInsensitive { regexOpts.insert(.caseInsensitive) }
                    if let regex = try? NSRegularExpression(pattern: query, options: regexOpts) {
                        let range = NSRange(location: 0, length: nsText.length)
                        for m in regex.matches(in: text, range: range) where m.range.length > 0 {
                            matches.append(InDocumentMatch(
                                blockId: block.id,
                                utf16Location: m.range.location,
                                utf16Length: m.range.length,
                                preview: text
                            ))
                        }
                    }
                } else {
                    var compareOpts: NSString.CompareOptions = []
                    if options.caseInsensitive { compareOpts.insert(.caseInsensitive) }
                    if options.diacriticsInsensitive { compareOpts.insert(.diacriticInsensitive) }

                    var searchLocation = 0
                    while searchLocation < nsText.length {
                        let remaining = NSRange(location: searchLocation, length: nsText.length - searchLocation)
                        let found = nsText.range(of: query, options: compareOpts, range: remaining)
                        if found.location == NSNotFound || found.length == 0 { break }
                        matches.append(InDocumentMatch(
                            blockId: block.id,
                            utf16Location: found.location,
                            utf16Length: found.length,
                            preview: text
                        ))
                        searchLocation = found.location + found.length
                    }
                }
            }
            for child in block.subblocks {
                scanBlock(child)
            }
        }

        for block in document.blocks {
            scanBlock(block)
        }
        return matches
    }

    // MARK: - Inverted Index Mechanics

    private func insertRecord(_ rec: IndexedRecord) {
        records[rec.id] = rec
        for token in rec.tokens {
            invertedIndex[token, default: []].insert(rec.id)
        }
    }

    private func removeRecord(id: String) {
        guard let existing = records.removeValue(forKey: id) else { return }
        for token in existing.tokens {
            invertedIndex[token]?.remove(id)
            if invertedIndex[token]?.isEmpty == true {
                invertedIndex.removeValue(forKey: token)
            }
        }
    }

    /// Uses inverted token prefix intersection so queries avoid scanning unrelated documents.
    private func candidateRecordIDs(for foldedQuery: String) -> Set<String> {
        let terms = tokenize(foldedQuery)
        guard !terms.isEmpty else { return Set(records.keys) }

        var intersection: Set<String>?
        for term in terms {
            var termMatches = Set<String>()
            for (indexedToken, ids) in invertedIndex where indexedToken.hasPrefix(term) || indexedToken.contains(term) {
                termMatches.formUnion(ids)
            }
            if let current = intersection {
                intersection = current.intersection(termMatches)
            } else {
                intersection = termMatches
            }
            if intersection?.isEmpty == true { return [] }
        }
        return intersection ?? []
    }

    private func matchesTier(_ rec: IndexedRecord, tier: SearchMaxDepth, context: WorkspaceDestination) -> Bool {
        switch tier {
        case .currentView:
            switch context {
            case .document(let docId):
                return rec.ownerDocumentId == docId
            case .calendar, .tasks:
                if case .task = rec.kind { return true }
                return false
            case .folder(let folderId):
                return rec.folderId == folderId
            case .tag(let tagName):
                return rec.tags.contains(tagName)
            case .connections:
                if case .connection = rec.kind { return true }
                return false
            case .sharedWithMe:
                if case .sharedDocument = rec.kind { return true }
                return false
            case .settings:
                if case .settingsSection = rec.kind { return true }
                return false
            case .allDocs, .trash:
                if case .document = rec.kind { return true }
                if case .folder = rec.kind { return true }
                return false
            }
        case .relatedScope:
            return !rec.isDeepBlockBody
        case .everything:
            return true
        }
    }

    private func scoreMatch(_ rec: IndexedRecord, fullQuery: String, terms: [String], tier: SearchMaxDepth) -> Int? {
        guard terms.allSatisfy({ rec.foldedSearchText.contains($0) }) else { return nil }
        let foldedTitle = fold(rec.title)
        var score = 20
        if foldedTitle == fullQuery { score += 120 }
        else if foldedTitle.hasPrefix(fullQuery) { score += 80 }
        else if foldedTitle.contains(fullQuery) { score += 50 }
        if tier == .currentView { score += 100 }
        return score
    }

    private func scopeLabel(for rec: IndexedRecord, tier: SearchMaxDepth) -> String {
        if tier == .currentView { return "Current View" }
        switch rec.kind {
        case .task: return "Task"
        case .document: return "Document"
        case .block: return "In Document"
        case .folder: return "Folder"
        case .tag: return "Tag"
        case .connection: return "Connection"
        case .sharedDocument: return "Shared"
        case .settingsSection: return "Settings"
        }
    }

    // MARK: - Record Builders

    private func makeDocumentRecords(_ doc: RoweDocument) -> [IndexedRecord] {
        var result: [IndexedRecord] = []
        let docTitle = doc.displayTitle
        let docTags = Set(doc.tags)

        if !doc.isHiddenTaskDocument {
            let docText = fold("\(docTitle) \(doc.tags.joined(separator: " ")) \(doc.previewSnippet)")
            result.append(IndexedRecord(
                id: "doc:\(doc.id)",
                kind: .document(documentId: doc.id),
                title: docTitle,
                subtitle: doc.previewSnippet,
                foldedSearchText: docText,
                tokens: Set(tokenize(docText)),
                ownerDocumentId: doc.id,
                folderId: doc.folderId,
                tags: docTags,
                isDeepBlockBody: false
            ))
        }

        func walk(_ blocks: [Block]) {
            for b in blocks {
                if b.isTask {
                    let notes = b.task?.notes ?? ""
                    let dateStr = b.task?.scheduleDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Unscheduled"
                    let raw = "\(b.content) \(notes) \(docTitle) \(dateStr)"
                    let folded = fold(raw)
                    result.append(IndexedRecord(
                        id: "task:\(b.id)",
                        kind: .task(documentId: doc.id, blockId: b.id),
                        title: b.content.isEmpty ? "Untitled Task" : b.content,
                        subtitle: "\(b.task?.isInbox == true ? "Inbox" : docTitle) · \(dateStr)",
                        foldedSearchText: folded,
                        tokens: Set(tokenize(folded)),
                        ownerDocumentId: doc.id,
                        folderId: doc.folderId,
                        tags: docTags,
                        isDeepBlockBody: false
                    ))
                } else {
                    var bodyParts = [b.content]
                    if let table = b.tableData {
                        bodyParts.append(contentsOf: table.cells.flatMap { $0.map(\.rawContent) })
                    }
                    if let col = b.collectionData {
                        bodyParts.append(col.title)
                        bodyParts.append(contentsOf: col.rows.flatMap { $0.values.values })
                    }
                    let joined = bodyParts.filter { !$0.isEmpty }.joined(separator: " ")
                    if !joined.isEmpty {
                        let folded = fold(joined)
                        result.append(IndexedRecord(
                            id: "blk:\(b.id)",
                            kind: .block(documentId: doc.id, blockId: b.id),
                            title: String(joined.prefix(90)),
                            subtitle: docTitle,
                            foldedSearchText: folded,
                            tokens: Set(tokenize(folded)),
                            ownerDocumentId: doc.id,
                            folderId: doc.folderId,
                            tags: docTags,
                            isDeepBlockBody: true
                        ))
                    }
                }
                if !b.subblocks.isEmpty { walk(b.subblocks) }
            }
        }
        walk(doc.blocks)
        return result
    }

    private func makeFolderRecord(_ folder: Folder) -> IndexedRecord {
        let folded = fold(folder.name)
        return IndexedRecord(
            id: "folder:\(folder.id)",
            kind: .folder(folderId: folder.id),
            title: folder.name,
            subtitle: "Folder",
            foldedSearchText: folded,
            tokens: Set(tokenize(folded)),
            ownerDocumentId: nil,
            folderId: folder.id,
            tags: [],
            isDeepBlockBody: false
        )
    }

    private func makeTagRecord(_ tag: TagItem) -> IndexedRecord {
        let folded = fold(tag.name)
        return IndexedRecord(
            id: "tag:\(tag.id)",
            kind: .tag(name: tag.name),
            title: "#\(tag.name)",
            subtitle: tag.isPinned ? "Pinned Tag" : "Tag",
            foldedSearchText: folded,
            tokens: Set(tokenize(folded)),
            ownerDocumentId: nil,
            folderId: nil,
            tags: [tag.name],
            isDeepBlockBody: false
        )
    }

    private func makeConnectionRecord(_ conn: ConnectionItem) -> IndexedRecord {
        let folded = fold("\(conn.name) \(conn.kind.rawValue) \(conn.endpointURL) \(conn.documentScope.rawValue)")
        return IndexedRecord(
            id: "conn:\(conn.id)",
            kind: .connection(connectionId: conn.id),
            title: conn.name,
            subtitle: "\(conn.kind.rawValue) · \(conn.documentScope.rawValue)",
            foldedSearchText: folded,
            tokens: Set(tokenize(folded)),
            ownerDocumentId: nil,
            folderId: nil,
            tags: [],
            isDeepBlockBody: false
        )
    }

    private func makeSharedRecord(_ item: SharedDocumentItem) -> IndexedRecord {
        let folded = fold("\(item.title) \(item.sharedByName) \(item.preview)")
        return IndexedRecord(
            id: "shared:\(item.id)",
            kind: .sharedDocument(sharedId: item.id),
            title: item.title,
            subtitle: "Shared by \(item.sharedByName)",
            foldedSearchText: folded,
            tokens: Set(tokenize(folded)),
            ownerDocumentId: nil,
            folderId: nil,
            tags: [],
            isDeepBlockBody: false
        )
    }

    private func makeSettingsRecords() -> [IndexedRecord] {
        let specs: [(id: String, subtitle: String, keywords: String)] = [
            ("Stats", "Settings · Storage, Documents, Blocks, Words, Reading Time", "stats storage documents blocks pages words characters reading time metrics"),
            ("Space Settings", "Settings · Space Name & Profile Picture", "space settings name avatar picture photo icon"),
            ("Appearance & Sound", "Settings · Theme, Accent Color, Haptics, App Icon", "appearance sound haptics light dark clear tinted icon accent color animations"),
            ("Advanced", "Settings · Global Search Depth, Cache, Calendar, Tasks", "advanced search depth cache index calendar completed tasks date links week start"),
            ("Account Settings", "Settings · Local Profile, Display Name, Email, Bio", "account profile display name email bio photo avatar cloud sync"),
            ("Notifications", "Settings · Push, Email, Daily Digest", "notifications push email daily reminders"),
            ("Diagnostics", "Settings · Sync Status, Sync Now, Sync History", "diagnostics sync status history reset upload"),
            ("About", "Settings · App Version & Architecture", "about version rowe swiftui architecture")
        ]
        return specs.map { spec in
            let folded = fold("\(spec.id) \(spec.subtitle) \(spec.keywords)")
            return IndexedRecord(
                id: "settings:\(spec.id)",
                kind: .settingsSection(sectionId: spec.id),
                title: spec.id,
                subtitle: spec.subtitle,
                foldedSearchText: folded,
                tokens: Set(tokenize(folded)),
                ownerDocumentId: nil,
                folderId: nil,
                tags: [],
                isDeepBlockBody: false
            )
        }
    }

    // MARK: - LRU Cache & Tokenization

    private func touchCacheKey(_ key: CacheKey) {
        if let idx = cacheOrder.firstIndex(of: key) {
            cacheOrder.remove(at: idx)
        }
        cacheOrder.append(key)
    }

    private func storeInCache(_ key: CacheKey, response: ContextualSearchResponse) {
        queryCache[key] = response
        touchCacheKey(key)
        trimCacheIfNeeded()
    }

    private func trimCacheIfNeeded() {
        guard cacheLimit >= 0 else { return }
        while cacheOrder.count > cacheLimit {
            let evicted = cacheOrder.removeFirst()
            queryCache.removeValue(forKey: evicted)
        }
    }

    private func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func tokenize(_ foldedText: String) -> [String] {
        foldedText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
