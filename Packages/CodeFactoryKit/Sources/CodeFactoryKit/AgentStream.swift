import Foundation

/// Something Claude Code wanted to do but wasn't allowed to.
public struct PermissionDenial: Codable, Hashable, Sendable {
    public var tool: String
    /// The file or folder involved, when the tool touches one.
    public var path: String?
    /// The shell command, for Bash.
    public var command: String?

    public init(tool: String, path: String? = nil, command: String? = nil) {
        self.tool = tool
        self.path = path
        self.command = command
    }

    /// "Read ~/reviewdesk/README.md" or "Run `npm install`".
    public var summary: String {
        if let command { return "Run `\(command.prefix(80))`" }
        if let path { return "\(tool) \((path as NSString).abbreviatingWithTildeInPath)" }
        return tool
    }

    /// The folder to grant so this would be allowed next time, if any.
    public func directoryToAllow(outside repository: URL) -> URL? {
        guard let path, path.hasPrefix("/") else { return nil }
        let url = URL(filePath: path)
        let repo = repository.path
        if url.path == repo || url.path.hasPrefix(repo + "/") { return nil }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return Project.canonical(url)
        }
        return Project.canonical(url.deletingLastPathComponent())
    }
}

/// What a headless run amounted to, read from its stream-json log.
public struct RunSummary: Codable, Hashable, Sendable {
    public var result: String
    public var denials: [PermissionDenial]
    public var isError: Bool
    public var costUSD: Double?

    /// Folders that would unblock the denied tools.
    public func directoriesToAllow(outside repository: URL) -> [URL] {
        var seen = Set<String>()
        return denials.compactMap { $0.directoryToAllow(outside: repository) }
            .filter { seen.insert($0.path).inserted }
    }
}

/// Reads Claude Code's `--output-format stream-json` output.
public enum AgentStream {
    /// The final summary, from the last `result` event.
    public static func summary(of log: String) -> RunSummary? {
        var summary: RunSummary?
        for line in log.split(separator: "\n") {
            guard let event = object(line), event["type"] as? String == "result" else { continue }
            let denials = (event["permission_denials"] as? [[String: Any]] ?? []).map(denial)
            summary = RunSummary(
                result: cleaned(event["result"] as? String ?? ""),
                denials: denials,
                isError: event["is_error"] as? Bool ?? false,
                costUSD: event["total_cost_usd"] as? Double
            )
        }
        return summary
    }

    /// A readable transcript for the console: what the agent said, which
    /// tools it used, and anything that was refused. Non-JSON lines pass through.
    public static func render(_ log: String) -> String {
        var out: [String] = []
        for line in log.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let event = object(line) else {
                if !line.isEmpty { out.append(String(line)) }
                continue
            }
            switch event["type"] as? String {
            case "assistant":
                for block in content(event) {
                    switch block["type"] as? String {
                    case "text":
                        let text = cleaned(block["text"] as? String ?? "")
                        if !text.isEmpty { out.append("● " + text) }
                    case "tool_use":
                        out.append("  ⏺ " + toolLine(block["name"] as? String ?? "Tool", block["input"] as? [String: Any] ?? [:]))
                    default: break
                    }
                }
            case "user":
                for block in content(event) where block["type"] as? String == "tool_result" && block["is_error"] as? Bool == true {
                    let text = (block["content"] as? String) ?? ""
                    out.append("    ✗ " + text.prefix(200))
                }
            case "result":
                let denials = (event["permission_denials"] as? [[String: Any]] ?? []).map(denial)
                if !denials.isEmpty {
                    out.append("")
                    out.append("⚠ Needed permission for:")
                    out += denials.map { "   • " + $0.summary }
                }
                if let cost = event["total_cost_usd"] as? Double {
                    out.append(String(format: "\n✓ Finished · $%.2f", cost))
                }
            default:
                break
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: Helpers

    private static func object(_ line: Substring) -> [String: Any]? {
        guard line.first == "{", let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func content(_ event: [String: Any]) -> [[String: Any]] {
        ((event["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
    }

    private static func denial(_ raw: [String: Any]) -> PermissionDenial {
        let input = raw["tool_input"] as? [String: Any] ?? [:]
        return PermissionDenial(
            tool: raw["tool_name"] as? String ?? "Tool",
            path: (input["file_path"] ?? input["path"] ?? input["notebook_path"]) as? String,
            command: input["command"] as? String
        )
    }

    private static func toolLine(_ name: String, _ input: [String: Any]) -> String {
        if let command = input["command"] as? String { return "\(name)(\(command.prefix(100)))" }
        if let path = (input["file_path"] ?? input["path"] ?? input["notebook_path"]) as? String {
            return "\(name)(\((path as NSString).abbreviatingWithTildeInPath))"
        }
        if let pattern = input["pattern"] as? String { return "\(name)(\(pattern.prefix(80)))" }
        return name
    }

    /// Drops HTML comments (some setups add hidden markers) and trims.
    static func cleaned(_ text: String) -> String {
        text.replacing(/<!--[\s\S]*?-->/, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
