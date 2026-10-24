import Foundation

/// A repository you build with Ultra Code Factory. Its cards live in
/// `<repository>/.codefactory/` unless `cardsOverride` points elsewhere
/// (for example a folder in an Obsidian vault).
public struct Project: Identifiable, Codable, Hashable, Sendable {
    public static let cardsFolderName = ".codefactory"

    public var id: String
    public var name: String
    public var repository: URL { didSet { repository = Self.canonical(repository) } }
    public var cardsOverride: URL? { didSet { cardsOverride = cardsOverride.map(Self.canonical) } }
    /// Folders outside the repository that agents may read and write
    /// (passed to Claude Code as `--add-dir`).
    public var allowedDirectories: [URL] = []

    public init(
        id: String = UUID().uuidString,
        name: String? = nil,
        repository: URL,
        cardsOverride: URL? = nil,
        allowedDirectories: [URL] = []
    ) {
        self.id = id
        self.repository = Self.canonical(repository)
        self.name = name ?? Self.canonical(repository).lastPathComponent
        self.cardsOverride = cardsOverride.map(Self.canonical)
        self.allowedDirectories = allowedDirectories.map(Self.canonical)
    }

    enum CodingKeys: String, CodingKey { case id, name, repository, cardsOverride, allowedDirectories }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            repository: try c.decode(URL.self, forKey: .repository),
            cardsOverride: try c.decodeIfPresent(URL.self, forKey: .cardsOverride),
            allowedDirectories: try c.decodeIfPresent([URL].self, forKey: .allowedDirectories) ?? []
        )
    }

    /// The path exactly as it is spelled on disk. macOS volumes are usually
    /// case-insensitive, but Claude Code compares paths exactly, so
    /// `~/Projects/app` and `~/projects/app` must not both appear.
    public static func canonical(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        let fd = open(standardized.path, O_RDONLY | O_EVTONLY)
        guard fd >= 0 else { return standardized }
        defer { close(fd) }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &buffer) != -1 else { return standardized }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(filePath: path, directoryHint: url.hasDirectoryPath ? .isDirectory : .inferFromPath)
    }

    /// Every folder an agent needs beyond the repository: the cards folder
    /// when it lives elsewhere, plus anything you've allowed.
    public var extraDirectories: [URL] {
        var dirs = allowedDirectories
        if !cardsRoot.path.hasPrefix(repository.path + "/") { dirs.insert(cardsRoot, at: 0) }
        var seen = Set<String>()
        return dirs.filter { seen.insert($0.path).inserted }
    }

    public var cardsRoot: URL {
        cardsOverride ?? repository.appending(path: Self.cardsFolderName, directoryHint: .isDirectory)
    }

    public var board: CardBoard { CardBoard(root: cardsRoot, project: id) }

    /// The repository folder, if it is still there.
    public func validatedRepository() throws -> URL {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repository.path, isDirectory: &isDir), isDir.boolValue else {
            throw CardError.notFound(repository.path)
        }
        return repository
    }
}

/// The list of projects, persisted as JSON.
public struct ProjectStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    public func load() -> [Project] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Project].self, from: data)) ?? []
    }

    public func save(_ projects: [Project]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(projects).write(to: fileURL, options: [.atomic])
    }
}
