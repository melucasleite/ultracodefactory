import Foundation

/// A repository you build with Code Factory. Its cards live in
/// `<repository>/.codefactory/` unless `cardsOverride` points elsewhere
/// (for example a folder in an Obsidian vault).
public struct Project: Identifiable, Codable, Hashable, Sendable {
    public static let cardsFolderName = ".codefactory"

    public var id: String
    public var name: String
    public var repository: URL
    public var cardsOverride: URL?

    public init(id: String = UUID().uuidString, name: String? = nil, repository: URL, cardsOverride: URL? = nil) {
        self.id = id
        self.repository = repository.standardizedFileURL
        self.name = name ?? repository.standardizedFileURL.lastPathComponent
        self.cardsOverride = cardsOverride?.standardizedFileURL
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
