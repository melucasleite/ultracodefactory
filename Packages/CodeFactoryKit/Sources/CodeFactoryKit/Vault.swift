import Foundation

public enum VaultError: LocalizedError, Equatable {
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

/// A folder of markdown work cards laid out as `<work>/<project>/<status>/<card>.md`.
///
/// Every name that comes from the outside world passes through `segment(_:)`
/// before touching the filesystem, so nothing can climb out of the work root.
public struct Vault: Sendable {
    public let workRoot: URL

    public init(workRoot: URL) {
        self.workRoot = workRoot.standardizedFileURL
    }

    public init(vaultRoot: URL, workFolder: String) {
        self.init(workRoot: vaultRoot.appending(path: workFolder, directoryHint: .isDirectory))
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
        else { throw VaultError.invalidName(name) }
        return name
    }

    func projectURL(_ project: String) throws -> URL {
        workRoot.appending(path: try Self.segment(project), directoryHint: .isDirectory)
    }

    func statusURL(_ project: String, _ status: CardStatus) throws -> URL {
        try projectURL(project).appending(path: status.rawValue, directoryHint: .isDirectory)
    }

    public func cardURL(project: String, status: CardStatus, file: String) throws -> URL {
        let name = try Self.segment(file)
        guard name.hasSuffix(".md") else { throw VaultError.invalidName(file) }
        return try statusURL(project, status).appending(path: name, directoryHint: .notDirectory)
    }

    // MARK: Reading

    public var exists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: workRoot.path, isDirectory: &isDir) && isDir.boolValue
    }

    public func listProjects() throws -> [String] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: workRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func listCards(project: String) throws -> [Card] {
        var cards: [Card] = []
        for status in CardStatus.allCases {
            let dir = try statusURL(project, status)
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue } // a project need not have every status folder
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
                    priority: fm.fields["priority"].nonEmpty
                ))
            }
        }
        return cards.sorted { lhs, rhs in
            (lhs.updated ?? "", rhs.file) > (rhs.updated ?? "", lhs.file)
        }
    }

    public func read(project: String, status: CardStatus, file: String) throws -> String {
        try String(contentsOf: cardURL(project: project, status: status, file: file), encoding: .utf8)
    }

    // MARK: Writing

    public func write(project: String, status: CardStatus, file: String, content: String) throws {
        let url = try cardURL(project: project, status: status, file: file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Moves a card to another column, stamping `status:` and `updated:` in its
    /// frontmatter. Refuses to clobber a same-named card in the destination.
    public func move(project: String, file: String, from: CardStatus, to: CardStatus, today: Date = .now) throws {
        guard from != to else { return }
        let source = try cardURL(project: project, status: from, file: file)
        let destination = try cardURL(project: project, status: to, file: file)
        guard FileManager.default.fileExists(atPath: source.path) else { throw VaultError.notFound(source.path) }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw VaultError.alreadyExists(destination.path)
        }
        let content = try String(contentsOf: source, encoding: .utf8)
        let updated = Frontmatter.updating(content, with: ["status": to.rawValue, "updated": Self.dayStamp(today)])
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.write(to: destination, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: source)
    }

    /// Moves a card to the macOS Trash rather than deleting it outright.
    public func trash(project: String, status: CardStatus, file: String) throws {
        let url = try cardURL(project: project, status: status, file: file)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Creates a new card from a title, returning its filename.
    @discardableResult
    public func create(
        project: String,
        title: String,
        kind: String = "feature",
        status: CardStatus = .proposed,
        body: String = "",
        today: Date = .now
    ) throws -> String {
        let base = Self.slug(title)
        var file = "\(base).md"
        var n = 2
        while FileManager.default.fileExists(atPath: try cardURL(project: project, status: status, file: file).path) {
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
        try write(project: project, status: status, file: file, content: content)
        return file
    }

    public func createProject(_ name: String) throws {
        let url = try projectURL(name)
        for status in CardStatus.allCases {
            try FileManager.default.createDirectory(
                at: url.appending(path: status.rawValue, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
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
