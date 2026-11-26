import Foundation

/// Background actor for Markdown import/export, HTML, and Plain Text conversion.
public actor ExportServiceActor {
    public init() {}

    public func exportMarkdown(document: RoweDocument) -> String {
        var lines: [String] = []
        if !document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("# \(document.title)")
            lines.append("")
        }
        renderBlocksMarkdown(document.blocks, into: &lines)
        return lines.joined(separator: "\n")
    }

    public func exportPlainText(document: RoweDocument) -> String {
        var lines: [String] = []
        if !document.title.isEmpty {
            lines.append(document.title)
            lines.append("")
        }
        func walk(_ blocks: [Block]) {
            for b in blocks {
                let indent = String(repeating: "  ", count: b.indentLevel)
                switch b.kind {
                case .line:
                    lines.append("---")
                case .table:
                    if let table = b.tableData {
                        for row in table.cells {
                            lines.append(row.map(\.rawContent).joined(separator: "\t"))
                        }
                    }
                default:
                    lines.append(indent + b.content)
                }
                walk(b.subblocks)
            }
        }
        walk(document.blocks)
        return lines.joined(separator: "\n")
    }

    public func exportHTML(document: RoweDocument) -> String {
        let escapedTitle = escapeHTML(document.displayTitle)
        var body: [String] = ["<h1>\(escapedTitle)</h1>"]
        for block in document.blocks {
            body.append(renderBlockHTML(block))
        }
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8" />
        <title>\(escapedTitle)</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 720px; margin: 48px auto; color: #1F2225; line-height: 1.5; }
          pre { background: #F5F5F7; padding: 12px 16px; border-radius: 8px; overflow-x: auto; }
          blockquote { border-left: 3px solid #D0D4DA; margin: 12px 0; padding-left: 14px; color: #4A4F57; }
          table { border-collapse: collapse; width: 100%; margin: 16px 0; }
          th, td { border: 1px solid #E2E5EA; padding: 8px 10px; text-align: left; }
        </style>
        </head>
        <body>
        \(body.joined(separator: "\n"))
        </body>
        </html>
        """
    }

    /// Parses Markdown into Rowe blocks following Craft's Maaku rules (headings, code blocks,
    /// horizontal rules, blockquotes as `focus` decoration, lists, todos).
    public func importMarkdown(_ markdown: String, spaceId: String, folderId: String? = nil, defaultTitle: String = "Imported Document") -> RoweDocument {
        let docId = UUID().uuidString
        let rawLines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var title = defaultTitle
        var hasExplicitTitle = false
        var blocks: [Block] = []

        var i = 0
        while i < rawLines.count {
            let line = rawLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < rawLines.count && !rawLines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(rawLines[i])
                    i += 1
                }
                blocks.append(Block(
                    documentId: docId,
                    kind: .code,
                    content: codeLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                    codeLanguage: lang.isEmpty ? "text" : lang
                ))
                i += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(Block(documentId: docId, kind: .line, content: "---"))
                i += 1
                continue
            }

            if trimmed.isEmpty {
                i += 1
                continue
            }

            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let indent = min(leadingSpaces / 2, 6)

            if trimmed.hasPrefix("# ") && !hasExplicitTitle {
                title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                hasExplicitTitle = true
            } else if trimmed.hasPrefix("# ") {
                blocks.append(Block(documentId: docId, content: String(trimmed.dropFirst(2)), textStyle: .title))
            } else if trimmed.hasPrefix("## ") {
                blocks.append(Block(documentId: docId, content: String(trimmed.dropFirst(3)), textStyle: .subtitle))
            } else if trimmed.hasPrefix("### ") {
                blocks.append(Block(documentId: docId, content: String(trimmed.dropFirst(4)), textStyle: .heading))
            } else if trimmed.hasPrefix("> ") {
                blocks.append(Block(documentId: docId, content: String(trimmed.dropFirst(2)), decoration: .focus))
            } else if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("* [ ] ") {
                blocks.append(Block(
                    documentId: docId,
                    content: String(trimmed.dropFirst(6)),
                    listStyle: .todo,
                    indentLevel: indent,
                    task: TaskMetadata(state: .pending)
                ))
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                blocks.append(Block(
                    documentId: docId,
                    content: String(trimmed.dropFirst(6)),
                    listStyle: .todo,
                    indentLevel: indent,
                    task: TaskMetadata(state: .completed, checkedDate: Date())
                ))
            } else if trimmed.hasPrefix("- [-] ") {
                blocks.append(Block(
                    documentId: docId,
                    content: String(trimmed.dropFirst(6)),
                    listStyle: .todo,
                    indentLevel: indent,
                    task: TaskMetadata(state: .canceled, checkedDate: Date())
                ))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(Block(documentId: docId, content: String(trimmed.dropFirst(2)), listStyle: .bullet, indentLevel: indent))
            } else if let dotRange = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                let text = String(trimmed[dotRange.upperBound...])
                blocks.append(Block(documentId: docId, content: text, listStyle: .numbered, indentLevel: indent))
            } else {
                blocks.append(Block(documentId: docId, content: trimmed, indentLevel: indent))
            }
            i += 1
        }

        if blocks.isEmpty {
            blocks.append(Block(documentId: docId, content: ""))
        }

        return RoweDocument(id: docId, spaceId: spaceId, folderId: folderId, title: title, blocks: blocks)
    }

    private func renderBlocksMarkdown(_ blocks: [Block], into lines: inout [String]) {
        var numberedCounter = 0
        for block in blocks {
            if block.listStyle == .numbered {
                numberedCounter += 1
            } else {
                numberedCounter = 0
            }
            let indent = String(repeating: "  ", count: block.indentLevel)

            switch block.kind {
            case .line:
                lines.append("---")
            case .code:
                lines.append("```\(block.codeLanguage)")
                lines.append(block.content)
                lines.append("```")
            case .table:
                if let table = block.tableData, !table.cells.isEmpty {
                    for (idx, row) in table.cells.enumerated() {
                        lines.append("| " + row.map(\.rawContent).joined(separator: " | ") + " |")
                        if idx == 0 {
                            lines.append("| " + row.map { _ in "---" }.joined(separator: " | ") + " |")
                        }
                    }
                }
            default:
                var prefix = ""
                if block.decoration == .focus { prefix += "> " }
                switch block.textStyle {
                case .title: prefix += "# "
                case .subtitle: prefix += "## "
                case .heading: prefix += "### "
                default: break
                }
                switch block.listStyle {
                case .bullet: prefix += "- "
                case .numbered: prefix += "\(numberedCounter). "
                case .toggle: prefix += "- "
                case .todo:
                    let mark: String
                    switch block.task?.state ?? .pending {
                    case .pending: mark = " "
                    case .completed: mark = "x"
                    case .canceled: mark = "-"
                    }
                    prefix += "- [\(mark)] "
                case .none: break
                }
                lines.append(indent + prefix + block.content)
            }

            if !block.subblocks.isEmpty {
                renderBlocksMarkdown(block.subblocks, into: &lines)
            }
        }
    }

    private func renderBlockHTML(_ block: Block) -> String {
        let content = escapeHTML(block.content)
        switch block.kind {
        case .line: return "<hr />"
        case .code: return "<pre><code>\(content)</code></pre>"
        case .table:
            guard let table = block.tableData else { return "" }
            let rowsHTML = table.cells.enumerated().map { idx, row in
                let tag = (idx == 0 && table.hasHeaderRow) ? "th" : "td"
                return "<tr>" + row.map { "<\(tag)>\(escapeHTML($0.rawContent))</\(tag)>" }.joined() + "</tr>"
            }.joined(separator: "\n")
            return "<table>\(rowsHTML)</table>"
        default:
            if block.decoration == .focus { return "<blockquote>\(content)</blockquote>" }
            switch block.textStyle {
            case .title: return "<h1>\(content)</h1>"
            case .subtitle: return "<h2>\(content)</h2>"
            case .heading: return "<h3>\(content)</h3>"
            default: return "<p>\(content)</p>"
            }
        }
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Recursively imports a Craft export folder (or single file) preserving subfolder structure as Rowe folders.
    /// Supports Craft Markdown exports (.md, .markdown, .txt) and Craft v2 JSON document exports (.json).
    public func importCraftDirectory(
        at rootURL: URL,
        spaceId: String,
        existingFolderNames: [String: String]
    ) -> (newFolders: [Folder], documents: [RoweDocument]) {
        let fm = FileManager.default
        var folderMap = existingFolderNames
        var newFolders: [Folder] = []
        var importedDocs: [RoweDocument] = []

        func ensureFolder(named name: String) -> String {
            if let existing = folderMap[name] { return existing }
            let created = Folder(spaceId: spaceId, name: name, iconName: "folder", sortOrder: folderMap.count)
            folderMap[name] = created.id
            newFolders.append(created)
            return created.id
        }

        let isDir = (try? rootURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let fileURLs: [URL]
        if isDir {
            var collected: [URL] = []
            if let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator {
                    let ext = url.pathExtension.lowercased()
                    if ["md", "markdown", "txt", "json"].contains(ext) {
                        collected.append(url)
                    }
                }
            }
            fileURLs = collected
        } else {
            fileURLs = [rootURL]
        }

        for fileURL in fileURLs {
            let ext = fileURL.pathExtension.lowercased()
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let parentName = fileURL.deletingLastPathComponent().lastPathComponent
            let folderName = (isDir && parentName != rootURL.lastPathComponent) ? parentName : "Craft Import"
            let folderId = ensureFolder(named: folderName)

            if ext == "json", let data = try? Data(contentsOf: fileURL),
               let jsonDoc = parseCraftJSONDocument(data: data, spaceId: spaceId, folderId: folderId, fallbackTitle: baseName) {
                importedDocs.append(jsonDoc)
            } else if let text = try? String(contentsOf: fileURL, encoding: .utf8),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let doc = importMarkdown(text, spaceId: spaceId, folderId: folderId, defaultTitle: baseName)
                importedDocs.append(doc)
            }
        }

        return (newFolders, importedDocs)
    }

    private func parseCraftJSONDocument(data: Data, spaceId: String, folderId: String?, fallbackTitle: String) -> RoweDocument? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let docId = UUID().uuidString
        let title = (root["content"] as? String) ?? (root["title"] as? String) ?? fallbackTitle
        guard let subBlocks = root["subBlocks"] as? [[String: Any]] else { return nil }

        var blocks: [Block] = []
        for raw in subBlocks {
            let content = (raw["content"] as? String) ?? (raw["text"] as? String) ?? ""
            let typeStr = (raw["type"] as? String) ?? "text"
            let styleDict = raw["styleAttributes"] as? [String: Any]
            let indent = (styleDict?["indentationLevel"] as? Int) ?? 0

            if typeStr == "line" {
                blocks.append(Block(documentId: docId, kind: .line, content: "---", indentLevel: indent))
                continue
            }
            if typeStr == "code" {
                let lang = (raw["properties"] as? [String: Any])?["language"] as? String ?? "swift"
                blocks.append(Block(documentId: docId, kind: .code, content: content, indentLevel: indent, codeLanguage: lang))
                continue
            }

            let textStyle: BlockTextStyle = switch styleDict?["textStyle"] as? String {
            case "title": .title
            case "subtitle": .subtitle
            case "heading": .heading
            case "strong": .strong
            case "caption": .caption
            case "pageRegular": .pageRegular
            case "pageCard": .pageCard
            default: .body
            }
            let listStyle: BlockListStyle = switch styleDict?["listStyle"] as? String {
            case "bullet": .bullet
            case "numbered": .numbered
            case "todo": .todo
            case "toggle": .toggle
            default: .none
            }
            let decorations = styleDict?["decorations"] as? [String: Any]
            let dec: BlockDecoration = (decorations?["block"] != nil) ? .block : ((decorations?["focus"] != nil) ? .focus : .none)

            var taskMeta: TaskMetadata?
            if listStyle == .todo {
                let checked = (raw["properties"] as? [String: Any])?["isTodoChecked"] as? String
                let state: TaskCompletionState = checked == "1" ? .completed : (checked == "2" ? .canceled : .pending)
                taskMeta = TaskMetadata(state: state)
            }

            blocks.append(Block(
                documentId: docId,
                kind: .text,
                content: content,
                textStyle: textStyle,
                listStyle: listStyle,
                indentLevel: indent,
                decoration: dec,
                task: taskMeta
            ))
        }

        if blocks.isEmpty {
            blocks.append(Block(documentId: docId, content: ""))
        }
        return RoweDocument(id: docId, spaceId: spaceId, folderId: folderId, title: title, blocks: blocks)
    }
}
