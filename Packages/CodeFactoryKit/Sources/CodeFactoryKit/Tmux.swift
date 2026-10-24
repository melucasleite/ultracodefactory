import Foundation

/// Keys the console may forward to an interactive session. Anything outside
/// this list is rejected, so a caller can never smuggle in tmux key bindings.
public enum NamedKey: String, CaseIterable, Sendable {
    case up = "Up"
    case down = "Down"
    case left = "Left"
    case right = "Right"
    case enter = "Enter"
    case escape = "Escape"
    case tab = "Tab"
    case backTab = "BTab"
    case space = "Space"
    case backspace = "BSpace"
    case interrupt = "C-c"
}

/// Thin, injection-safe wrapper around the tmux CLI.
public struct Tmux: Sendable {
    public let binary: URL

    public init(binary: URL) {
        self.binary = binary
    }

    /// tmux session names may not contain `.` or `:`; we only ever mint
    /// `[A-Za-z0-9-]` names, and refuse anything else.
    public static func validate(session: String) throws -> String {
        guard !session.isEmpty, session.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw CardError.invalidName(session)
        }
        return session
    }

    /// Starts a detached session running `command` directly (no shell).
    public func newSession(
        name: String,
        directory: URL,
        command: [String],
        environment: [String: String] = [:],
        width: Int = 200,
        height: Int = 50
    ) async throws {
        var args = ["new-session", "-d", "-s", try Self.validate(session: name), "-c", directory.path,
                    "-x", String(width), "-y", String(height)]
        for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
            args += ["-e", "\(key)=\(value)"]
        }
        // With more than one word, tmux execs the command directly instead of via `sh -c`.
        args += command
        try await ProcessRunner.run(binary, args)
    }

    public func hasSession(_ name: String) async -> Bool {
        guard let name = try? Self.validate(session: name) else { return false }
        let result = try? await ProcessRunner.run(binary, ["has-session", "-t", "=\(name)"], check: false)
        return result?.status == 0
    }

    /// The visible pane plus `history` lines of scrollback. With `escapes`,
    /// SGR colour sequences are kept so the console can render them.
    public func capture(_ name: String, history: Int = 200, escapes: Bool = true) async throws -> String {
        var args = ["capture-pane", "-p", "-t", try Self.validate(session: name), "-S", "-\(history)"]
        if escapes { args.append("-e") }
        let result = try await ProcessRunner.run(binary, args)
        var text = result.stdout
        while text.hasSuffix("\n") { text.removeLast() }
        return text
    }

    public func send(_ key: NamedKey, to name: String) async throws {
        try await ProcessRunner.run(binary, ["send-keys", "-t", try Self.validate(session: name), key.rawValue])
    }

    /// Types `text` literally (`-l`), so words like "Enter" are never read as key names.
    public func type(_ text: String, to name: String) async throws {
        guard !text.isEmpty else { return }
        try await ProcessRunner.run(binary, ["send-keys", "-t", try Self.validate(session: name), "-l", "--", text])
    }

    public func kill(_ name: String) async throws {
        try await ProcessRunner.run(binary, ["kill-session", "-t", "=\(try Self.validate(session: name))"])
    }
}
