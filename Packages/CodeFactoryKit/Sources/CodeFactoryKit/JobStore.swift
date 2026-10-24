import Foundation

/// Persists the job ledger as JSON so the board and the jobs list survive
/// relaunches, and reconciles each job with the real world on refresh.
public actor JobStore {
    public let fileURL: URL
    private var jobs: [Job]

    /// Claude Code prints this while it is busy; when it disappears from an
    /// interactive pane, the agent is idle and most likely waiting on you.
    public static let busyMarker = "esc to interrupt"

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL), let decoded = try? decoder.decode([Job].self, from: data) {
            jobs = decoded
        } else {
            jobs = []
        }
    }

    public func all() -> [Job] {
        jobs.sorted { $0.startedAt > $1.startedAt }
    }

    public func job(_ id: String) -> Job? {
        jobs.first { $0.id == id }
    }

    public func add(_ job: Job) throws {
        jobs.append(job)
        try save()
    }

    public func update(_ id: String, _ change: @Sendable (inout Job) -> Void) throws {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
        try save()
    }

    public func removeFinished(project: String? = nil) throws {
        jobs.removeAll { !$0.state.isActive && (project == nil || $0.project == project) }
        try save()
    }

    /// Re-derives every active job's state from tmux and the process table.
    @discardableResult
    public func refresh(tmux: Tmux?, executableName: String) async -> [Job] {
        var changed = false
        for index in jobs.indices where jobs[index].state.isActive {
            let job = jobs[index]
            switch job.mode {
            case .interactive:
                guard let session = job.session, let tmux, await tmux.hasSession(session) else {
                    jobs[index].state = .completed
                    jobs[index].finishedAt = .now
                    changed = true
                    continue
                }
                let pane = (try? await tmux.capture(session, history: 0, escapes: false)) ?? ""
                let next: Job.State = pane.contains(Self.busyMarker) ? .running : .waiting
                if next != job.state {
                    jobs[index].state = next
                    changed = true
                }
            case .headless:
                let alive = LiveProcesses.shared.isRunning(job.id) || (job.pid.map {
                    ProcessInspector.isOurs(pid: $0, startedAt: job.startedAt, executableName: executableName)
                } ?? false)
                if !alive {
                    jobs[index].state = (job.exitCode ?? 0) == 0 ? .completed : .failed
                    jobs[index].finishedAt = jobs[index].finishedAt ?? .now
                    changed = true
                }
            }
        }
        if changed { try? save() }
        return all()
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(jobs).write(to: fileURL, options: [.atomic])
    }
}
