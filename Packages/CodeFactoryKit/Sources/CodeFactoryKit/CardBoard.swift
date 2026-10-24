import Foundation

public enum CardError: LocalizedError, Equatable {
    case invalidName(String)
    case notFound(String)
    case alreadyExists(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name): "“\(name)” is not a valid file or folder name."
        case .notFound(let path): "Nothing at \(path)."
        case .alreadyExists(let path): "A card already exists at \(path)."
        }
    }
}

/// One project's cards: a folder holding a subfolder per status, with one
/// markdown file per card — `<root>/<status>/<card>.md`.
///
/// Every name that comes from the outside world passes through `segment(_:)`
/// before touching the filesystem, so nothing can climb out of the root.
public struct CardBoard: Sendable {
    public let root: URL
    /// The owning project's id, stamped on every card listed.
    public let project: String

    public init(root: URL, project: String) {
        self.root = root.standardizedFileURL
        self.project = project
    }

    // MARK: Paths

    /// Validates one path component: no separators, no traversal, no hidden files.
    public static func segment(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed == name,
              !name.contains("/"),
              !name.contains("\\"),
              !name.contains("\0"),
              !name.hasPrefix("."),
              name.count <= 255
        else { throw CardError.invalidName(name) }
        return name
    }

    func statusURL(_ status: CardStatus) -> URL {
        root.appending(path: status.rawValue, directoryHint: .isDirectory)
    }

    public func cardURL(status: CardStatus, file: String) throws -> URL {
        let name = try Self.segment(file)
        guard name.hasSuffix(".md") else { throw CardError.invalidName(file) }
        return statusURL(status).appending(path: name, directoryHint: .notDirectory)
    }

    // MARK: Reading

    public var exists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) && isDir.boolValue
    }

    public func listCards() -> [Card] {
        var cards: [Card] = []
        for status in CardStatus.allCases {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: statusURL(status), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue } // a board need not have every status folder
            for url in files where url.pathExtension == "md" {
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let fm = Frontmatter.parse(content)
                let file = url.lastPathComponent
                cards.append(Card(
                    project: project,
                    status: status,
                    file: file,
                    title: fm.fields["title"].nonEmpty ?? String(file.dropLast(3)),
                    cardID: fm.fields["id"].nonEmpty,
                    kind: fm.fields["kind"].nonEmpty,
                    updated: fm.fields["updated"].nonEmpty,
                    priority: fm.fields["priority"].nonEmpty,
                    order: fm.fields["order"].flatMap { Int($0) },
                    pullRequest: fm.fields["pr"].flatMap(URL.init(string:)) ?? Card.pullRequestURL(in: fm.body)
                ))
            }
        }
        return cards.sorted(by: Card.executionOrder)
    }

    public func read(status: CardStatus, file: String) throws -> String {
        try String(contentsOf: cardURL(status: status, file: file), encoding: .utf8)
    }

    // MARK: Writing

    /// Creates the six status folders (harmless if they exist).
    public func prepare() throws {
        for status in CardStatus.allCases {
            try FileManager.default.createDirectory(at: statusURL(status), withIntermediateDirectories: true)
        }
    }

    public func write(status: CardStatus, file: String, content: String) throws {
        let url = try cardURL(status: status, file: file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Moves a card to another column, stamping `status:` and `updated:` in its
    /// frontmatter. Refuses to clobber a same-named card in the destination.
    public func move(file: String, from: CardStatus, to: CardStatus, today: Date = .now) throws {
        guard from != to else { return }
        let source = try cardURL(status: from, file: file)
        let destination = try cardURL(status: to, file: file)
        guard FileManager.default.fileExists(atPath: source.path) else { throw CardError.notFound(source.path) }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CardError.alreadyExists(destination.path)
        }
        let content = try String(contentsOf: source, encoding: .utf8)
        let updated = Frontmatter.updating(content, with: ["status": to.rawValue, "updated": Self.dayStamp(today)])
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.write(to: destination, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: source)
    }

    /// Puts a card just before `target` (or last when `target` is nil) in
    /// the project's execution order, then renumbers every card's `order:`
    /// 1…n. Cards keep their relative order otherwise; only `order:` lines
    /// change, and only on cards whose number actually changes.
    public func reorder(file: String, in status: CardStatus, before target: (file: String, status: CardStatus)?) throws {
        var cards = listCards()
        guard let moving = cards.firstIndex(where: { $0.file == file && $0.status == status }) else {
            throw CardError.notFound(file)
        }
        let card = cards.remove(at: moving)
        let index = target.flatMap { t in cards.firstIndex { $0.file == t.file && $0.status == t.status } } ?? cards.endIndex
        cards.insert(card, at: index)
        try renumber(cards.map { ($0.file, $0.status) })
    }

    /// Writes `order:` 1…n onto the given cards, in that order.
    public func renumber(_ cards: [(file: String, status: CardStatus)]) throws {
        for (offset, card) in cards.enumerated() {
            let content = try read(status: card.status, file: card.file)
            let wanted = String(offset + 1)
            guard Frontmatter.parse(content).fields["order"] != wanted else { continue }
            try write(status: card.status, file: card.file, content: Frontmatter.updating(content, with: ["order": wanted]))
        }
    }

    /// Moves a card to the macOS Trash rather than deleting it outright.
    public func trash(status: CardStatus, file: String) throws {
        try FileManager.default.trashItem(at: cardURL(status: status, file: file), resultingItemURL: nil)
    }

    /// Creates a new card from a title, returning its filename.
    @discardableResult
    public func create(
        title: String,
        kind: String = "feature",
        status: CardStatus = .proposed,
        body: String = "",
        today: Date = .now
    ) throws -> String {
        let base = Self.slug(title)
        var file = "\(base).md"
        var n = 2
        while FileManager.default.fileExists(atPath: try cardURL(status: status, file: file).path) {
            file = "\(base)-\(n).md"
            n += 1
        }
        let day = Self.dayStamp(today)
        let safeTitle = title.replacingOccurrences(of: "\n", with: " ")
        let content = """
        ---
        title: \(safeTitle)
        status: \(status.rawValue)
        kind: \(kind)
        created: \(day)
        updated: \(day)
        ---

        \(body.isEmpty ? "## Goal\n\n\n## Acceptance criteria\n\n- [ ] " : body)

        """
        try write(status: status, file: file, content: content)
        return file
    }

    // MARK: Helpers

    public static func slug(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US"))
        var out = ""
        var lastDash = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                out.unicodeScalars.append(scalar)
                lastDash = false
            } else if !lastDash, !out.isEmpty {
                out.append("-")
                lastDash = true
            }
            if out.count >= 60 { break }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "card" : out
    }

    static func dayStamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
