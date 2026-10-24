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

        out += "\n---\n\n_Created with Ultra Code Factory. Cards live in `.codefactory/`; agents read this brief first._\n"
        return out
    }
}

/// The built-in prompt for the agent that proposes a starter backlog. It
/// needs no user skills, so a fresh install can plan on its own.
public enum BacklogPlanner {
    /// The most cards one planning run may write.
    public static let maximumCards = 50

    public static func prompt(cardsFolder: URL, references: [URL] = [], today: Date = .now, fromExistingCode: Bool) -> String {
        let day = today.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let source = fromExistingCode
            ? "Explore this repository to understand what it does, how it is built and what looks unfinished, fragile or missing. Read PROJECT.md or README.md if present."
            : "Read PROJECT.md: it is the brief for a brand-new project, so the repository is otherwise empty."
        let referenceNote = references.isEmpty ? "" : """

        You can also read these folders, which the brief may mention by a shorter or older path. Use them as references; do not modify them:
        \(references.map { "- " + $0.path }.joined(separator: "\n"))
        """
        return """
        You are planning the backlog for this project. Do not write any application code and do not change any file outside the cards folder.

        \(source)\(referenceNote)

        Then write as many work cards as the project genuinely needs, between 10 and \(maximumCards), one markdown file each, into this folder (it already exists):
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

/// Turns a one-paragraph pitch into suggested wizard answers, using a quick
/// read-only `claude -p` call. Everything it returns is a suggestion: the
/// wizard shows it as pre-selected chips you can change.
public enum BriefSuggester {
    public struct Suggestion: Codable, Equatable, Sendable {
        public var platforms: [String] = []
        public var stack: [String] = []
        public var features: [String] = []
        public var designStyle: String?
        public var appearance: String?
    }

    public static func prompt(name: String, summary: String, platforms: [String], styles: [String], appearances: [String]) -> String {
        """
        A solo builder is starting a new software project and described it like this.

        Name: \(name)
        Pitch: \(summary)

        Suggest how to build it. Reply with ONLY a JSON object, no prose and no code fence, shaped like:
        {"platforms": [...], "stack": [...], "features": [...], "designStyle": "...", "appearance": "..."}

        Rules:
        - "platforms": one or more of exactly these strings: \(platforms.map { "\"\($0)\"" }.joined(separator: ", "))
        - "stack": 1 to 4 mainstream, well-supported technologies that fit those platforms.
        - "features": 5 to 8 short feature names (2 to 5 words each) a first version needs, most important first.
        - "designStyle": exactly one of: \(styles.map { "\"\($0)\"" }.joined(separator: ", "))
        - "appearance": exactly one of: \(appearances.map { "\"\($0)\"" }.joined(separator: ", "))
        """
    }

    /// Pulls the first JSON object out of a model reply and keeps only
    /// values the wizard understands.
    public static func parse(_ reply: String, platforms: [String], styles: [String], appearances: [String]) -> Suggestion? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let data = String(reply[start...end]).data(using: .utf8),
              var s = try? JSONDecoder().decode(Suggestion.self, from: data)
        else { return nil }
        s.platforms = s.platforms.filter(platforms.contains)
        s.stack = Array(s.stack.map(clean).filter { !$0.isEmpty }.prefix(4))
        s.features = Array(s.features.map(clean).filter { !$0.isEmpty }.prefix(8))
        if let style = s.designStyle, !styles.contains(style) { s.designStyle = nil }
        if let look = s.appearance, !appearances.contains(look) { s.appearance = nil }
        return s
    }

    /// Runs the suggestion in an empty scratch folder with read-only permissions.
    public static func suggest(
        name: String, summary: String, platforms: [String], styles: [String], appearances: [String], claude: URL
    ) async throws -> Suggestion? {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "codefactory-suggest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let result = try await ProcessRunner.run(
            claude,
            ["-p", prompt(name: name, summary: summary, platforms: platforms, styles: styles, appearances: appearances),
             "--permission-mode", PermissionMode.plan.rawValue],
            currentDirectory: scratch
        )
        return parse(result.stdout, platforms: platforms, styles: styles, appearances: appearances)
    }

    private static func clean(_ s: String) -> String {
        String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
    }
}
