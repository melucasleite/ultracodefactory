import Darwin
import Foundation

/// How much latitude a launched agent gets. Maps to Claude Code's
/// `--permission-mode`. The default is the most conservative mode that still
/// lets an unattended agent edit files; bypassing permissions is opt-in.
public enum PermissionMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case `default`
    case acceptEdits
    case plan
    case bypassPermissions

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .default: "Ask for everything"
        case .acceptEdits: "Accept file edits"
        case .plan: "Plan only (read-only)"
        case .bypassPermissions: "Bypass all permissions"
        }
    }

    public var isDangerous: Bool { self == .bypassPermissions }
}

public enum LaunchError: LocalizedError {
    case missingBinary(String)
    case missingRepository(URL)
    case emptyPrompt

    public var errorDescription: String? {
        switch self {
        case .missingBinary(let name): "Couldn’t find `\(name)`. Set its path in Settings → Agents."
        case .missingRepository(let url): "No repository at \(url.path). It may have moved — use Locate Repository… on the project."
        case .emptyPrompt: "Give the agent something to do first."
        }
    }
}

/// Everything needed to put an agent to work. Plain values so it can be
/// captured and sent across actors freely.
public struct LaunchConfiguration: Sendable {
    public var claude: URL?
    public var tmux: URL?
    public var logsDirectory: URL
    public var permissionMode: PermissionMode
    public var extraArguments: [String]
    /// Extra environment for agents, e.g. where the vault lives.
    public var environment: [String: String]

    public init(
        claude: URL?,
        tmux: URL?,
        logsDirectory: URL,
        permissionMode: PermissionMode,
        extraArguments: [String] = [],
        environment: [String: String] = [:]
    ) {
        self.claude = claude
        self.tmux = tmux
        self.logsDirectory = logsDirectory
        self.permissionMode = permissionMode
        self.extraArguments = extraArguments
        self.environment = environment
    }

    /// What an agent needs to find its own board.
    func environment(for project: Project) -> [String: String] {
        environment.merging([
            "CODE_FACTORY_PROJECT": project.name,
            "CODE_FACTORY_CARDS": project.cardsRoot.path,
        ]) { _, new in new }
    }

    func repository(for project: Project) throws -> URL {
        do {
            return try project.validatedRepository()
        } catch {
            throw LaunchError.missingRepository(project.repository)
        }
    }

    var agentArguments: [String] {
        ["--permission-mode", permissionMode.rawValue] + extraArguments
    }
}

public enum AgentLauncher {
    /// Runs `claude -p <prompt>` detached in the project repo, logging to a file.
    /// The process outlives the app; `onExit` fires only if it ends while we're running.
    public static func startHeadless(
        project: Project,
        prompt: String,
        action: String,
        config: LaunchConfiguration,
        onExit: @escaping @Sendable (String, Int32) -> Void
    ) throws -> Job {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LaunchError.emptyPrompt }
        guard let claude = config.claude else { throw LaunchError.missingBinary("claude") }
        let repo = try config.repository(for: project)
        let id = Job.newID()

        try FileManager.default.createDirectory(at: config.logsDirectory, withIntermediateDirectories: true)
        let log = config.logsDirectory.appending(path: "\(id).log")
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: log)

        let process = Process()
        process.executableURL = claude
        process.arguments = ["-p", trimmed, "--output-format", "stream-json", "--verbose"]
            + config.agentArguments + addDirArguments(project)
        process.currentDirectoryURL = repo
        process.environment = ProcessRunner.environment.merging(config.environment(for: project)) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        process.terminationHandler = { finished in
            try? handle.close()
            LiveProcesses.shared.remove(id)
            onExit(id, finished.terminationStatus)
        }
        try process.run()
        LiveProcesses.shared.insert(process, for: id)

        return Job(
            id: id,
            project: project.name,
            projectID: project.id,
            prompt: trimmed,
            action: action,
            mode: .headless,
            pid: process.processIdentifier,
            logPath: log.path
        )
    }

    /// Starts an interactive Claude Code session inside a detached tmux session.
    public static func startInteractive(
        project: Project,
        prompt: String,
        action: String,
        config: LaunchConfiguration
    ) async throws -> Job {
        guard let claude = config.claude else { throw LaunchError.missingBinary("claude") }
        guard let tmuxURL = config.tmux else { throw LaunchError.missingBinary("tmux") }
        let repo = try config.repository(for: project)
        let id = Job.newID()
        let session = "codefactory-\(id)"
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        var command = [claude.path]
        if !trimmed.isEmpty { command.append(trimmed) }
        command += config.agentArguments + addDirArguments(project)

        try await Tmux(binary: tmuxURL).newSession(
            name: session,
            directory: repo,
            command: command,
            environment: config.environment(for: project)
                .merging(["PATH": ProcessRunner.environment["PATH"] ?? ""]) { _, new in new }
        )
        return Job(
            id: id,
            project: project.name,
            projectID: project.id,
            prompt: trimmed.isEmpty ? "(interactive session)" : trimmed,
            action: action,
            mode: .interactive,
            session: session
        )
    }

    /// `--add-dir` for every folder the project lets agents use beyond the repo.
    static func addDirArguments(_ project: Project) -> [String] {
        project.extraDirectories.flatMap { ["--add-dir", $0.path] }
    }

    /// Stops a job: kills its tmux session, or sends SIGTERM to a headless
    /// process — but only after confirming the PID is still our agent.
    public static func stop(_ job: Job, tmux: URL?, executableName: String) async throws {
        switch job.mode {
        case .interactive:
            if let session = job.session, let tmux { try await Tmux(binary: tmux).kill(session) }
        case .headless:
            if let pid = job.pid, LiveProcesses.shared.isRunning(job.id)
                || ProcessInspector.isOurs(pid: pid, startedAt: job.startedAt, executableName: executableName) {
                Darwin.kill(pid, SIGTERM)
            }
        }
    }
}

/// Keeps launched `Process` objects alive until they exit so their
/// termination handlers are guaranteed to fire.
final class LiveProcesses: @unchecked Sendable {
    static let shared = LiveProcesses()
    private let lock = NSLock()
    private var processes: [String: Process] = [:]

    func insert(_ process: Process, for id: String) {
        lock.withLock { processes[id] = process }
    }

    func remove(_ id: String) {
        lock.withLock { _ = processes.removeValue(forKey: id) }
    }

    /// Whether this app launched `id` itself and it is still running — the
    /// most reliable liveness signal, whatever the executable turned out to be.
    func isRunning(_ id: String) -> Bool {
        lock.withLock { processes[id]?.isRunning ?? false }
    }
}
