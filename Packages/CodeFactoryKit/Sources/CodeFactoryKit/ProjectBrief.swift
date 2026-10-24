import Foundation

/// What the New Project wizard learns about a brand-new project. It becomes
/// `PROJECT.md` in the repository: the brief every agent reads first.
public struct ProjectBrief: Codable, Hashable, Sendable {
    public var name: String
    public var summary: String
    public var platforms: [String]
    /// Chosen stacks; empty means "let the agents choose".
    public var stack: [String]
    public var features: [String]
    public var designStyle: String?
    public var appearance: String?
    public var accentHex: String?
    public var notes: String

    public init(
        name: String = "",
        summary: String = "",
        platforms: [String] = [],
        stack: [String] = [],
        features: [String] = [],
        designStyle: String? = nil,
        appearance: String? = nil,
        accentHex: String? = nil,
        notes: String = ""
    ) {
        self.name = name
        self.summary = summary
        self.platforms = platforms
        self.stack = stack
        self.features = features
        self.designStyle = designStyle
        self.appearance = appearance
        self.accentHex = accentHex
        self.notes = notes
    }

    public var markdown: String {
        var out = "# \(name.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty { out += "\(trimmedSummary)\n\n" }

        out += "## Platforms\n\n"
        out += platforms.isEmpty ? "- To be decided\n" : platforms.map { "- \($0)\n" }.joined()

        out += "\n## Stack\n\n"
        out += stack.isEmpty
            ? "- Not chosen yet: pick a mainstream, well-supported stack for the platforms above and record the choice in a decision card.\n"
            : stack.map { "- \($0)\n" }.joined()

        out += "\n## Features\n\n"
        out += features.isEmpty ? "- To be discovered\n" : features.map { "- \($0)\n" }.joined()

        var design: [String] = []
        if let designStyle { design.append("Style: \(designStyle)") }
        if let appearance { design.append("Appearance: \(appearance)") }
        if let accentHex { design.append("Accent colour: \(accentHex)") }
        if !design.isEmpty {
            out += "\n## Design\n\n" + design.map { "- \($0)\n" }.joined()
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty { out += "\n## Notes\n\n\(trimmedNotes)\n" }

        out += "\n---\n\n_Created with Code Factory. Cards live in `.codefactory/`; agents read this brief first._\n"
        return out
    }
}

/// The built-in prompt for the agent that proposes a starter backlog. It
/// needs no user skills, so a fresh install can plan on its own.
public enum BacklogPlanner {
    public static func prompt(cardsFolder: URL, today: Date = .now, fromExistingCode: Bool) -> String {
        let day = today.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let source = fromExistingCode
            ? "Explore this repository to understand what it does, how it is built and what looks unfinished, fragile or missing. Read PROJECT.md or README.md if present."
            : "Read PROJECT.md: it is the brief for a brand-new project, so the repository is otherwise empty."
        return """
        You are planning the backlog for this project. Do not write any application code and do not change any file outside the cards folder.

        \(source)

        Then write between 8 and 15 work cards, one markdown file each, into this folder (it already exists):
        \(cardsFolder.appending(path: CardStatus.proposed.rawValue).path)

        Each file is named in kebab-case after its title, ends in .md, never overwrites an existing file, and looks like this:

        ---
        title: Short imperative title
        status: proposed
        kind: feature | bug | chore | refactor | spike | docs
        priority: high | medium | low
        created: \(day)
        updated: \(day)
        ---

        ## Goal

        One short paragraph: what and why.

        ## Acceptance criteria

        - [ ] Observable, testable outcome

        Order the work so foundations come first (project setup, tooling, CI, core data model), then the main features, then polish. Keep every card small enough to ship as a single pull request. When a decision is open, such as a stack choice the brief leaves to you, write it as a spike card. Finish by listing the cards you wrote.
        """
    }
}

public enum ScaffoldError: LocalizedError, Equatable {
    case folderNotEmpty(String)

    public var errorDescription: String? {
        switch self {
        case .folderNotEmpty(let path): "\(path) already exists and isn’t empty. Choose another name or location."
        }
    }
}

/// Creates the folder for a brand-new project.
public enum ProjectScaffold {
    /// Makes `<parent>/<slug(name)>`, writes `PROJECT.md`, prepares the cards
    /// folders and runs `git init`. Refuses to touch a non-empty folder.
    public static func create(in parent: URL, brief: ProjectBrief, git: URL? = URL(filePath: "/usr/bin/git")) async throws -> Project {
        let folder = parent.appending(path: CardBoard.slug(brief.name), directoryHint: .isDirectory)
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(atPath: folder.path), !contents.isEmpty {
            throw ScaffoldError.folderNotEmpty(folder.path)
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try brief.markdown.write(to: folder.appending(path: "PROJECT.md"), atomically: true, encoding: .utf8)

        let project = Project(name: brief.name.trimmingCharacters(in: .whitespacesAndNewlines), repository: folder)
        try project.board.prepare()

        if let git, fm.isExecutableFile(atPath: git.path) {
            try await ProcessRunner.run(git, ["init", "--quiet", "--initial-branch=main"], currentDirectory: folder)
            // The first commit is best effort: it needs a git identity configured.
            try? await ProcessRunner.run(git, ["add", "PROJECT.md"], currentDirectory: folder)
            try? await ProcessRunner.run(git, ["commit", "--quiet", "-m", "Project brief"], currentDirectory: folder)
        }
        return project
    }
}
