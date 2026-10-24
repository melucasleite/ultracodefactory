import Foundation

/// One thing an agent did: something it said, or a tool call with its result.
public struct ActivityStep: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case said, tool }

    public var id: String
    public var kind: Kind
    /// Tool name ("Bash", "Edit", …) for tool steps.
    public var tool: String?
    /// The headline: what was said, the command run, the file touched.
    public var title: String
    /// Extra context, e.g. Bash's description or an edit's line counts.
    public var subtitle: String?
    /// The tool's output, once it arrives.
    public var output: String?
    public var isError = false
    public var started: Date?
    public var finished: Date?

    public var isRunning: Bool { kind == .tool && output == nil }
    public var duration: TimeInterval? {
        guard let started, let finished else { return nil }
        return finished.timeIntervalSince(started)
    }
}

/// Reads Claude Code's session transcripts (and stream-json logs, which use
/// the same messages) into a readable activity timeline.
public struct ActivityParser: Sendable {
    public private(set) var steps: [ActivityStep] = []
    private var index: [String: Int] = [:]

    public init() {}

    /// Feeds complete JSONL lines; partial lines must be held back by the caller.
    public mutating func ingest(_ lines: some Sequence<Substring>) {
        for line in lines {
            guard line.first == "{", let data = line.data(using: .utf8),
                  let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            let time = (event["timestamp"] as? String).flatMap(Self.date)
            let content = ((event["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
            switch event["type"] as? String {
            case "assistant":
                for block in content {
                    switch block["type"] as? String {
                    case "text":
                        let text = AgentStream.cleaned(block["text"] as? String ?? "")
                        guard !text.isEmpty else { continue }
                        steps.append(ActivityStep(id: UUID().uuidString, kind: .said, title: text, started: time))
                    case "tool_use":
                        let id = block["id"] as? String ?? UUID().uuidString
                        let name = block["name"] as? String ?? "Tool"
                        let (title, subtitle) = Self.describe(name, block["input"] as? [String: Any] ?? [:])
                        index[id] = steps.count
                        steps.append(ActivityStep(id: id, kind: .tool, tool: name, title: title, subtitle: subtitle, started: time))
                    default: break
                    }
                }
            case "user":
                for block in content where block["type"] as? String == "tool_result" {
                    guard let id = block["tool_use_id"] as? String, let at = index[id] else { continue }
                    steps[at].output = Self.text(of: block["content"])
                    steps[at].isError = block["is_error"] as? Bool ?? false
                    steps[at].finished = time
                }
            default: break
            }
        }
    }

    /// Parses a whole transcript or log.
    public static func parse(_ text: String) -> [ActivityStep] {
        var parser = ActivityParser()
        parser.ingest(text.split(separator: "\n"))
        return parser.steps
    }

    // MARK: Helpers

    static func describe(_ tool: String, _ input: [String: Any]) -> (String, String?) {
        func path(_ key: String) -> String? {
            (input[key] as? String).map { ($0 as NSString).abbreviatingWithTildeInPath }
        }
        switch tool {
        case "Bash":
            return (input["command"] as? String ?? "", input["description"] as? String)
        case "Read":
            return (path("file_path") ?? "", nil)
        case "Write":
            let lines = (input["content"] as? String)?.split(separator: "\n", omittingEmptySubsequences: false).count
            return (path("file_path") ?? "", lines.map { "\($0) lines" })
        case "Edit":
            let removed = (input["old_string"] as? String)?.split(separator: "\n", omittingEmptySubsequences: false).count ?? 0
            let added = (input["new_string"] as? String)?.split(separator: "\n", omittingEmptySubsequences: false).count ?? 0
            return (path("file_path") ?? "", "+\(added) −\(removed)")
        case "MultiEdit":
            let edits = (input["edits"] as? [Any])?.count ?? 0
            return (path("file_path") ?? "", "\(edits) edits")
        case "Grep":
            return (input["pattern"] as? String ?? "", path("path"))
        case "Glob":
            return (input["pattern"] as? String ?? "", path("path"))
        case "Task", "Agent":
            return (input["description"] as? String ?? tool, input["subagent_type"] as? String)
        case "WebFetch":
            return (input["url"] as? String ?? "", nil)
        case "WebSearch":
            return (input["query"] as? String ?? "", nil)
        case "TodoWrite":
            let todos = (input["todos"] as? [[String: Any]]) ?? []
            let active = todos.first { $0["status"] as? String == "in_progress" }?["content"] as? String
            return (active ?? "Updated the plan", "\(todos.count) items")
        default:
            let first = input.values.compactMap { $0 as? String }.first ?? ""
            return (first, nil)
        }
    }

    static func text(of content: Any?) -> String {
        if let string = content as? String { return string }
        if let blocks = content as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func date(_ string: String) -> Date? {
        fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

/// Finds the Claude Code transcript for a session started in `directory`.
public enum ClaudeTranscript {
    /// `~/.claude/projects/<cwd with every non-alphanumeric character as "-">`.
    public static func folder(for directory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let encoded = directory.path.replacing(/[^A-Za-z0-9]/, with: "-")
        return home.appending(path: ".claude/projects/\(encoded)", directoryHint: .isDirectory)
    }

    /// The session file that began closest after `startedAt` (a worktree can
    /// hold several sessions, e.g. a worker and a later conflict fixer).
    public static func file(for directory: URL, startedAt: Date, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let folder = folder(for: directory, home: home)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        let dated = files.filter { $0.pathExtension == "jsonl" }.compactMap { url -> (URL, Date)? in
            guard let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate else { return nil }
            return (url, created)
        }
        let after = dated.filter { $0.1 >= startedAt.addingTimeInterval(-10) }.min { $0.1 < $1.1 }
        return after?.0 ?? dated.max { $0.1 < $1.1 }?.0
    }
}
