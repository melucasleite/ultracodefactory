import CodeFactoryKit
import Foundation
import Observation
import UserNotifications

/// The app's single source of truth: which vault, which project, its cards,
/// and every agent on the factory floor.
@MainActor
@Observable
final class FactoryModel {
    private(set) var projects: [String] = []
    /// Open (not done / won't do) card counts per project, for the sidebar.
    private(set) var openCounts: [String: Int] = [:]
    private(set) var cards: [Card] = []
    private(set) var jobs: [Job] = []
    private(set) var vaultReady = false
    var errorMessage: String?

    var selectedProject: String? {
        didSet {
            guard selectedProject != oldValue else { return }
            UserDefaults.standard.set(selectedProject, forKey: Pref.selectedProject)
            loadCards()
        }
    }

    @ObservationIgnored private let jobStore = JobStore(
        fileURL: Preferences.supportDirectory.appending(path: "jobs.json")
    )
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var watchedRoot: URL?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var lastStates: [String: Job.State] = [:]

    var prefs: Preferences { Preferences() }

    init() {
        Preferences.registerDefaults()
        selectedProject = UserDefaults.standard.string(forKey: Pref.selectedProject)
        configureVault()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.configureVault() }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshJobs()
                let busy = self?.jobs.contains { $0.state.isActive } ?? false
                try? await Task.sleep(for: .seconds(busy ? 1.5 : 6))
            }
        }
    }

    // MARK: Derived state

    var activeJobs: [Job] { jobs.filter(\.state.isActive) }
    var waitingJobs: [Job] { jobs.filter { $0.state == .waiting } }

    func jobs(for project: String) -> [Job] { jobs.filter { $0.project == project } }

    /// Headless create jobs still running — drawn as cards under construction.
    func fabricating(in project: String) -> [Job] {
        jobs.filter { $0.project == project && $0.action == LaunchAction.create.rawValue && $0.state.isActive }
    }

    var kinds: [String] {
        Array(Set(cards.compactMap(\.kind))).sorted()
    }

    // MARK: Vault

    /// (Re)binds to the vault in Preferences, restarting the file watcher only
    /// when the location actually changed.
    func configureVault() {
        guard let vault = prefs.vault else {
            vaultReady = false
            watcher?.stop()
            watcher = nil
            watchedRoot = nil
            projects = []
            cards = []
            return
        }
        vaultReady = vault.exists
        guard watchedRoot != vault.workRoot || watcher == nil else { return }
        watchedRoot = vault.workRoot
        watcher?.stop()
        watcher = vaultReady ? DirectoryWatcher(url: vault.workRoot) { [weak self] in self?.reload() } : nil
        reload()
    }

    func reload() {
        guard let vault = prefs.vault, vault.exists else {
            vaultReady = false
            return
        }
        vaultReady = true
        do {
            projects = try vault.listProjects()
            var counts: [String: Int] = [:]
            for project in projects {
                counts[project] = (try? vault.listCards(project: project))?
                    .filter { $0.status != .done && $0.status != .wontDo }.count ?? 0
            }
            openCounts = counts
            if selectedProject.map({ !projects.contains($0) }) ?? true {
                selectedProject = projects.first
            }
            loadCards()
        } catch {
            report(error)
        }
    }

    func loadCards() {
        guard let vault = prefs.vault, let project = selectedProject else {
            cards = []
            return
        }
        do {
            cards = try vault.listCards(project: project)
        } catch {
            cards = []
            report(error)
        }
    }

    // MARK: Cards

    func move(_ ref: CardReference, to status: CardStatus) {
        guard ref.status != status, let vault = prefs.vault else { return }
        // Optimistic: slide the tile now, let the watcher confirm.
        if let index = cards.firstIndex(where: { $0.project == ref.project && $0.status == ref.status && $0.file == ref.file }) {
            cards[index].status = status
        }
        do {
            try vault.move(project: ref.project, file: ref.file, from: ref.status, to: status)
        } catch {
            report(error)
        }
        reload()
    }

    func trash(_ card: Card) {
        do {
            try prefs.vault?.trash(project: card.project, status: card.status, file: card.file)
        } catch {
            report(error)
        }
        reload()
    }

    func read(_ card: Card) throws -> String {
        guard let vault = prefs.vault else { throw VaultError.notFound("vault") }
        return try vault.read(project: card.project, status: card.status, file: card.file)
    }

    func save(_ card: Card, content: String) throws {
        guard let vault = prefs.vault else { throw VaultError.notFound("vault") }
        try vault.write(project: card.project, status: card.status, file: card.file, content: content)
        reload()
    }

    func cardURL(_ card: Card) -> URL? {
        try? prefs.vault?.cardURL(project: card.project, status: card.status, file: card.file)
    }

    @discardableResult
    func createCard(title: String, kind: String, status: CardStatus) -> Card? {
        guard let vault = prefs.vault, let project = selectedProject else { return nil }
        do {
            let file = try vault.create(project: project, title: title, kind: kind, status: status)
            reload()
            return cards.first { $0.file == file && $0.status == status }
        } catch {
            report(error)
            return nil
        }
    }

    func createProject(_ name: String) {
        do {
            try prefs.vault?.createProject(name)
            reload()
            selectedProject = name
        } catch {
            report(error)
        }
    }

    // MARK: Agents

    private var launchConfiguration: LaunchConfiguration? {
        guard let repos = prefs.reposRoot else { return nil }
        return LaunchConfiguration(
            claude: prefs.claude,
            tmux: prefs.tmux,
            reposRoot: repos,
            logsDirectory: Preferences.supportDirectory.appending(path: "logs", directoryHint: .isDirectory),
            permissionMode: prefs.permissionMode,
            environment: [
                "CODE_FACTORY_VAULT": prefs.vaultRoot?.path ?? "",
                "CODE_FACTORY_WORK_FOLDER": prefs.workFolder,
            ]
        )
    }

    /// Builds the agent's first message: the configured slash command for the
    /// action, followed by whatever the user typed.
    func prompt(for action: LaunchAction, text: String) -> String {
        let command: String = switch action {
        case .create: prefs.createCommand
        case .work: prefs.workCommand
        case .triage: prefs.triageCommand
        case .session: ""
        }
        return [command, text.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    @discardableResult
    func launch(_ action: LaunchAction, project: String? = nil, text: String = "") async -> Job? {
        guard let project = project ?? selectedProject else { return nil }
        guard let config = launchConfiguration else {
            report(LaunchError.missingRepository(URL(filePath: "(no repositories folder set)")))
            return nil
        }
        requestNotificationPermissionIfNeeded()
        let prompt = prompt(for: action, text: text)
        do {
            let job: Job
            if action.isInteractive {
                job = try await AgentLauncher.startInteractive(project: project, prompt: prompt, action: action.rawValue, config: config)
            } else {
                job = try AgentLauncher.startHeadless(project: project, prompt: prompt, action: action.rawValue, config: config) { [weak self] id, status in
                    Task { @MainActor in await self?.headlessExited(id, status: status) }
                }
            }
            try await jobStore.add(job)
            lastStates[job.id] = job.state
            jobs = await jobStore.all()
            return job
        } catch {
            report(error)
            return nil
        }
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
        try? await jobStore.update(id) {
            guard $0.state.isActive else { return }
            $0.exitCode = status
            $0.state = status == 0 ? .completed : .failed
            $0.finishedAt = .now
        }
        await refreshJobs()
    }

    func refreshJobs() async {
        let tmux = prefs.tmux.map(Tmux.init)
        let updated = await jobStore.refresh(tmux: tmux, executableName: "claude")
        for job in updated {
            let previous = lastStates[job.id]
            lastStates[job.id] = job.state
            guard let previous, previous != job.state else { continue }
            announce(job, from: previous)
        }
        if updated != jobs { jobs = updated }
    }

    // MARK: Notifications

    private func announce(_ job: Job, from previous: Job.State) {
        if job.action == LaunchAction.create.rawValue, !job.state.isActive { reload() }
        guard prefs.notifications else { return }
        let content = UNMutableNotificationContent()
        content.threadIdentifier = job.project
        switch job.state {
        case .waiting where previous == .running:
            content.title = "\(job.project): your input is needed"
            content.body = job.prompt
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
