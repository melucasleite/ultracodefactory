import AppKit
import CodeFactoryKit
import Foundation
import Observation
import UserNotifications

/// The app's single source of truth: your projects, the selected one's
/// cards, and every agent on the factory floor.
@MainActor
@Observable
final class FactoryModel {
    private(set) var projects: [Project] = []
    /// Open (not done / won't do) card counts per project id, for the sidebar.
    private(set) var openCounts: [String: Int] = [:]
    private(set) var cards: [Card] = []
    /// Cards that just appeared (written by an agent, say), for a moment of glow.
    private(set) var freshCards: Set<String> = []
    private(set) var jobs: [Job] = []
    var errorMessage: String?
    /// Drives the New Project sheet from anywhere (sidebar, welcome, menu).
    var showingNewProject = false
    /// What happened while you were away; shown once when you come back.
    var awayReport: AwayReport?

    /// The selected project's id.
    var selectedProject: String? {
        didSet {
            guard selectedProject != oldValue else { return }
            UserDefaults.standard.set(selectedProject, forKey: Pref.selectedProject)
            loadCards()
        }
    }

    @ObservationIgnored private let projectStore = ProjectStore(
        fileURL: Preferences.supportDirectory.appending(path: "projects.json")
    )
    @ObservationIgnored private let jobStore = JobStore(
        fileURL: Preferences.supportDirectory.appending(path: "jobs.json")
    )
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastStates: [String: Job.State] = [:]
    @ObservationIgnored private var leftAt: Date?
    @ObservationIgnored private var activityObservers: [NSObjectProtocol] = []

    var prefs: Preferences { Preferences() }

    init() {
        Preferences.registerDefaults()
        projects = projectStore.load()
        selectedProject = UserDefaults.standard.string(forKey: Pref.selectedProject)
        projectsChanged()
        observeAppActivity()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshJobs()
                let busy = self?.jobs.contains { $0.state.isActive } ?? false
                try? await Task.sleep(for: .seconds(busy ? 1.5 : 6))
            }
        }
    }

    // MARK: Derived state

    var hasProjects: Bool { !projects.isEmpty }
    var selected: Project? { selectedProject.flatMap(project) }
    func project(_ id: String) -> Project? { projects.first { $0.id == id } }

    var activeJobs: [Job] { jobs.filter(\.state.isActive) }
    var waitingJobs: [Job] { jobs.filter { $0.state == .waiting } }

    func jobs(for projectID: String) -> [Job] { jobs.filter { $0.projectID == projectID } }

    /// Headless jobs still writing cards into `status` — drawn as cards under construction.
    func fabricating(in projectID: String, status: CardStatus) -> [Job] {
        jobs(for: projectID).filter {
            $0.state.isActive && LaunchAction(rawValue: $0.action)?.fabricatesInto == status
        }
    }

    var kinds: [String] {
        Array(Set(cards.compactMap(\.kind))).sorted()
    }

    // MARK: Projects

    /// Adds a repository as a project, creating its `.codefactory` card
    /// folders. Adding the same repository twice just selects it.
    @discardableResult
    func addProject(repository: URL) -> Project? {
        let url = Project.canonical(repository)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            report(CardError.notFound(url.path))
            return nil
        }
        if let existing = projects.first(where: { $0.repository == url }) {
            selectedProject = existing.id
            return existing
        }
        let project = Project(repository: url)
        do {
            try project.board.prepare()
        } catch {
            report(error)
            return nil
        }
        projects.append(project)
        projects.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        saveProjects()
        selectedProject = project.id
        return project
    }

    /// Forgets a project. Its repository and cards stay on disk.
    func removeProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        saveProjects()
        if selectedProject == project.id { selectedProject = projects.first?.id }
    }

    func updateProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        try? project.board.prepare()
        saveProjects()
    }

    private func saveProjects() {
        do {
            try projectStore.save(projects)
        } catch {
            report(error)
        }
        projectsChanged()
    }

    /// Rewatches every project's cards folder and reloads.
    private func projectsChanged() {
        watcher?.stop()
        let roots = projects.map(\.cardsRoot).filter { FileManager.default.fileExists(atPath: $0.path) }
        watcher = roots.isEmpty ? nil : DirectoryWatcher(urls: roots) { [weak self] in self?.reload() }
        reload()
    }

    func reload() {
        var counts: [String: Int] = [:]
        for project in projects {
            counts[project.id] = project.board.listCards().filter { $0.status != .done && $0.status != .wontDo }.count
        }
        openCounts = counts
        if selected == nil { selectedProject = projects.first?.id }
        loadCards()
    }

    func loadCards() {
        let next = selected?.board.listCards() ?? []
        // Anything new within the same project gets a short welcome glow.
        let previous = Set(cards.map(\.id))
        if let first = next.first, cards.first?.project == first.project, !previous.isEmpty {
            let arrived = Set(next.map(\.id)).subtracting(previous)
            if !arrived.isEmpty {
                freshCards.formUnion(arrived)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    self?.freshCards.subtract(arrived)
                }
            }
        }
        cards = next
    }

    // MARK: Cards

    private func board(_ projectID: String) throws -> CardBoard {
        guard let project = project(projectID) else { throw CardError.notFound("project") }
        return project.board
    }

    func move(_ ref: CardReference, to status: CardStatus) {
        guard ref.status != status else { return }
        // Optimistic: slide the tile now, let the watcher confirm.
        if let index = cards.firstIndex(where: { $0.project == ref.project && $0.status == ref.status && $0.file == ref.file }) {
            cards[index].status = status
        }
        do {
            try board(ref.project).move(file: ref.file, from: ref.status, to: status)
        } catch {
            report(error)
        }
        reload()
    }

    /// Moves a whole column, e.g. approving every proposed card into To-Do.
    func moveAll(from: CardStatus, to: CardStatus) {
        guard let selected else { return }
        do {
            let skipped = try selected.board.moveAll(from: from, to: to)
            if !skipped.isEmpty {
                errorMessage = "Left \(skipped.count) card\(skipped.count == 1 ? "" : "s") in \(from.title): a card with the same name is already in \(to.title)."
            }
        } catch {
            report(error)
        }
        reload()
    }

    /// Drops `ref` just before `target` in the build order, moving it to
    /// the target's column first if it came from another one.
    func place(_ ref: CardReference, before target: Card) {
        guard ref.project == target.project, !(ref.file == target.file && ref.status == target.status) else { return }
        do {
            let board = try board(ref.project)
            if ref.status != target.status {
                try board.move(file: ref.file, from: ref.status, to: target.status)
            }
            try board.reorder(file: ref.file, in: target.status, before: (target.file, target.status))
        } catch {
            report(error)
        }
        reload()
    }

    func trash(_ card: Card) {
        do {
            try board(card.project).trash(status: card.status, file: card.file)
        } catch {
            report(error)
        }
        reload()
    }

    func read(_ card: Card) throws -> String {
        try board(card.project).read(status: card.status, file: card.file)
    }

    func save(_ card: Card, content: String) throws {
        try board(card.project).write(status: card.status, file: card.file, content: content)
        reload()
    }

    func cardURL(_ card: Card) -> URL? {
        try? board(card.project).cardURL(status: card.status, file: card.file)
    }

    @discardableResult
    func createCard(title: String, kind: String, status: CardStatus) -> Card? {
        guard let selected else { return nil }
        do {
            let file = try selected.board.create(title: title, kind: kind, status: status)
            reload()
            return cards.first { $0.file == file && $0.status == status }
        } catch {
            report(error)
            return nil
        }
    }

    // MARK: Agents

    private var launchConfiguration: LaunchConfiguration {
        LaunchConfiguration(
            claude: prefs.claude,
            tmux: prefs.tmux,
            logsDirectory: Preferences.supportDirectory.appending(path: "logs", directoryHint: .isDirectory),
            permissionMode: prefs.permissionMode
        )
    }

    /// Builds the agent's first message: your slash command for the action if
    /// you set one in Settings, otherwise the built-in prompt.
    func prompt(for action: LaunchAction, project: Project, text: String) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = customCommand(for: action)
        if !command.isEmpty {
            return [command, text].filter { !$0.isEmpty }.joined(separator: " ")
        }
        switch action {
        case .create: return AgentPrompts.create(idea: text, cardsFolder: project.cardsRoot)
        case .work: return AgentPrompts.work(card: text.isEmpty ? nil : text, cardsFolder: project.cardsRoot)
        case .triage: return AgentPrompts.triage(cardsFolder: project.cardsRoot)
        case .session: return text
        case .plan: return BacklogPlanner.prompt(cardsFolder: project.cardsRoot, fromExistingCode: true)
        }
    }

    /// The slash command configured for an action, or "" for the built-in prompt.
    func customCommand(for action: LaunchAction) -> String {
        switch action {
        case .create: prefs.createCommand
        case .work: prefs.workCommand
        case .triage: prefs.triageCommand
        case .session, .plan: ""
        }
    }

    /// A short, human description of what an action will send.
    func jobLabel(for action: LaunchAction, text: String) -> String? {
        guard customCommand(for: action).isEmpty else { return nil }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case .create: return text.isEmpty ? nil : "Create: \(text)"
        case .work: return text.isEmpty ? "Work the next card" : "Work \(text)"
        case .triage: return "Triage the backlog"
        default: return nil
        }
    }

    @discardableResult
    func launch(
        _ action: LaunchAction,
        project projectID: String? = nil,
        text: String = "",
        fullPrompt: String? = nil,
        label: String? = nil
    ) async -> Job? {
        guard let id = projectID ?? selectedProject, let project = project(id) else { return nil }
        let config = launchConfiguration
        requestNotificationPermissionIfNeeded()
        let prompt = fullPrompt ?? prompt(for: action, project: project, text: text)
        let label = label ?? (fullPrompt == nil ? jobLabel(for: action, text: text) : nil)
        do {
            var job: Job
            if action.isInteractive {
                job = try await AgentLauncher.startInteractive(project: project, prompt: prompt, action: action.rawValue, config: config)
            } else {
                job = try AgentLauncher.startHeadless(project: project, prompt: prompt, action: action.rawValue, config: config) { [weak self] id, status in
                    Task { @MainActor in await self?.headlessExited(id, status: status) }
                }
            }
            // Show a short label instead of a long built-in prompt.
            if let label { job.prompt = label }
            job.instructions = prompt
            try await jobStore.add(job)
            lastStates[job.id] = job.state
            jobs = await jobStore.all()
            return job
        } catch {
            report(error)
            return nil
        }
    }

    /// Plans from the brief when the repo holds nothing but `PROJECT.md`,
    /// otherwise from the code.
    @discardableResult
    func planBacklog(for project: Project) async -> Job? {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: project.repository.path)) ?? []
        let onlyBrief = entries.filter { !$0.hasPrefix(".") && $0 != "PROJECT.md" }.isEmpty
        return await planBacklog(for: project, fromExistingCode: !onlyBrief)
    }

    /// Asks a headless agent to propose a starter backlog into Proposed.
    @discardableResult
    func planBacklog(for project: Project, fromExistingCode: Bool) async -> Job? {
        let prompt = BacklogPlanner.prompt(
            cardsFolder: project.cardsRoot, references: project.allowedDirectories, fromExistingCode: fromExistingCode
        )
        let label = fromExistingCode ? "Planning a starter backlog from the code" : "Planning a starter backlog from PROJECT.md"
        return await launch(.plan, project: project.id, fullPrompt: prompt, label: label)
    }

    func stop(_ job: Job) async {
        do {
            try await AgentLauncher.stop(job, tmux: prefs.tmux, executableName: "claude")
            try await jobStore.update(job.id) {
                $0.state = .stopped
                $0.finishedAt = .now
            }
            lastStates[job.id] = .stopped
        } catch {
            report(error)
        }
        await refreshJobs()
    }

    func clearFinished() async {
        try? await jobStore.removeFinished()
        jobs = await jobStore.all()
    }

    func job(_ id: String) -> Job? { jobs.first { $0.id == id } }

    private func headlessExited(_ id: String, status: Int32) async {
        let summary = await jobStore.job(id).flatMap(Self.readSummary)
        try? await jobStore.update(id) {
            guard $0.state.isActive else { return }
            $0.exitCode = status
            $0.state = status == 0 ? .completed : .failed
            $0.finishedAt = .now
            $0.summary = summary
        }
        await refreshJobs()
    }

    private static func readSummary(_ job: Job) -> RunSummary? {
        guard let path = job.logPath, let log = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return AgentStream.summary(of: log)
    }

    /// Fills in summaries for headless jobs that finished while we weren't watching.
    private func summarizeFinishedJobs(_ jobs: [Job]) async {
        for job in jobs where job.mode == .headless && !job.state.isActive && job.summary == nil {
            guard let summary = Self.readSummary(job) else { continue }
            try? await jobStore.update(job.id) { $0.summary = summary }
        }
    }

    /// Folders that would have let this job do what it was refused.
    func foldersToAllow(for job: Job) -> [URL] {
        guard let project = project(job.projectID), let summary = job.summary else { return [] }
        return summary.directoriesToAllow(outside: project.repository)
    }

    /// Grants the folders a job was refused, then runs it again.
    @discardableResult
    func allowAndRerun(_ job: Job) async -> Job? {
        guard var project = project(job.projectID) else { return nil }
        for folder in foldersToAllow(for: job) where !project.allowedDirectories.contains(folder) {
            project.allowedDirectories.append(folder)
        }
        updateProject(project)
        guard let action = LaunchAction(rawValue: job.action) else { return nil }
        return await launch(action, project: project.id, fullPrompt: job.instructions ?? job.prompt, label: job.prompt)
    }

    func allowFolder(_ folder: URL, for project: Project) {
        var updated = project
        let canonical = Project.canonical(folder)
        guard !updated.allowedDirectories.contains(canonical) else { return }
        updated.allowedDirectories.append(canonical)
        updateProject(updated)
    }

    func disallowFolder(_ folder: URL, for project: Project) {
        var updated = project
        updated.allowedDirectories.removeAll { $0 == folder }
        updateProject(updated)
    }

    func refreshJobs() async {
        let tmux = prefs.tmux.map(Tmux.init)
        var updated = await jobStore.refresh(tmux: tmux, executableName: "claude")
        if updated.contains(where: { $0.mode == .headless && !$0.state.isActive && $0.summary == nil && $0.logPath != nil }) {
            await summarizeFinishedJobs(updated)
            updated = await jobStore.all()
        }
        for job in updated {
            let previous = lastStates[job.id]
            lastStates[job.id] = job.state
            guard let previous, previous != job.state else { continue }
            announce(job, from: previous)
        }
        if updated != jobs { jobs = updated }
    }

    // MARK: While you were away

    private func observeAppActivity() {
        let center = NotificationCenter.default
        activityObservers = [
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.leftAt = .now }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.cameBack() }
            },
        ]
    }

    private func cameBack() async {
        guard let leftAt else { return }
        self.leftAt = nil
        guard Date.now.timeIntervalSince(leftAt) >= AwayReport.minimumAbsence else { return }
        await refreshJobs()
        let report = AwayReport(
            since: leftAt,
            finished: jobs.filter { $0.state == .completed && ($0.finishedAt ?? .distantPast) > leftAt }.count,
            failed: jobs.filter { $0.state == .failed && ($0.finishedAt ?? .distantPast) > leftAt }.count,
            waiting: waitingJobs.count,
            pullRequests: projects.flatMap { $0.board.listCards() }
                .filter { $0.pullRequest != nil && $0.status == .waiting }.count
        )
        if !report.isEmpty { awayReport = report }
    }

    // MARK: Notifications

    private func announce(_ job: Job, from previous: Job.State) {
        if LaunchAction(rawValue: job.action)?.fabricatesInto != nil, !job.state.isActive { reload() }
        guard prefs.notifications else { return }
        let content = UNMutableNotificationContent()
        content.threadIdentifier = job.project
        switch job.state {
        case .waiting where previous == .running:
            content.title = "\(job.project): your input is needed"
            content.body = job.prompt
        case .completed where job.neededPermission:
            content.title = "\(job.project): the agent needed permission"
            content.body = job.summary?.denials.prefix(2).map(\.summary).joined(separator: " · ") ?? job.prompt
        case .completed:
            content.title = "\(job.project): job finished"
            content.body = job.prompt
        case .failed:
            content.title = "\(job.project): job failed"
            content.body = "\(job.prompt) — exit \(job.exitCode ?? -1)"
        default:
            return
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: "\(job.id)-\(job.state.rawValue)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationPermissionIfNeeded() {
        guard prefs.notifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func report(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// A summary of the factory's work since you last looked.
struct AwayReport: Equatable {
    static let minimumAbsence: TimeInterval = 5 * 60

    var since: Date
    var finished: Int
    var failed: Int
    var waiting: Int
    var pullRequests: Int

    var isEmpty: Bool { finished + failed + waiting + pullRequests == 0 }

    var headline: String {
        pullRequests > 0 ? "\(pullRequests) pull request\(pullRequests == 1 ? "" : "s") ready for review"
            : waiting > 0 ? "\(waiting) agent\(waiting == 1 ? " is" : "s are") waiting for you"
            : "The line kept moving"
    }

    var details: [String] {
        var out: [String] = []
        if finished > 0 { out.append("\(finished) job\(finished == 1 ? "" : "s") finished") }
        if waiting > 0, pullRequests > 0 { out.append("\(waiting) waiting for you") }
        if failed > 0 { out.append("\(failed) failed") }
        return out
    }
}
