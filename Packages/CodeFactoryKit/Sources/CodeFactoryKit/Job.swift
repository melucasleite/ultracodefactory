import Foundation

/// One agent run on the factory floor.
public struct Job: Identifiable, Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// A detached `claude -p` process writing to a log file.
        case headless
        /// An interactive Claude Code TUI inside a detached tmux session.
        case interactive
    }

    public enum State: String, Codable, Sendable {
        case running
        /// Interactive session idle — usually Claude asking a question.
        case waiting
        case completed
        case failed
        case stopped

        public var isActive: Bool { self == .running || self == .waiting }
    }

    public var id: String
    public var project: String
    /// The full slash command or prompt the agent was started with.
    public var prompt: String
    /// Which launcher action produced the job (create, work, triage, custom).
    public var action: String
    public var mode: Mode
    public var state: State
    public var startedAt: Date
    public var finishedAt: Date?
    public var pid: Int32?
    public var session: String?
    public var logPath: String?
    public var exitCode: Int32?

    public init(
        id: String,
        project: String,
        prompt: String,
        action: String,
        mode: Mode,
        state: State = .running,
        startedAt: Date = .now,
        pid: Int32? = nil,
        session: String? = nil,
        logPath: String? = nil
    ) {
        self.id = id
        self.project = project
        self.prompt = prompt
        self.action = action
        self.mode = mode
        self.state = state
        self.startedAt = startedAt
        self.pid = pid
        self.session = session
        self.logPath = logPath
    }

    /// `[A-Za-z0-9-]` only — doubles as a tmux session suffix and a log filename.
    public static func newID(now: Date = .now) -> String {
        let time = String(UInt64(now.timeIntervalSince1970 * 1000), radix: 36)
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let random = String((0..<6).map { _ in alphabet.randomElement()! })
        return "job-\(time)-\(random)"
    }

    public var attachCommand: String? {
        session.map { "tmux attach -t \($0)" }
    }
}
