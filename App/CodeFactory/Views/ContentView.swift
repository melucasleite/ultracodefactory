import CodeFactoryKit
import SwiftUI

enum BoardSheet: Identifiable {
    case createWork(String)
    case newCard

    var id: String {
        switch self {
        case .createWork(let project): "create-\(project)"
        case .newCard: "new-card"
        }
    }
}

struct ContentView: View {
    @Environment(FactoryModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var showJobs = true
    @State private var openCard: Card?
    @State private var sheet: BoardSheet?
    @State private var search = ""
    @State private var kindFilter: String?

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            HStack(spacing: 0) {
                detail
                if showJobs && model.hasProjects {
                    JobsInspector()
                        .frame(width: 320)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .glassPanel(cornerRadius: 24)
                        .padding([.vertical, .trailing], 12)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    errorBanner
                    if let report = model.awayReport { AwayBanner(report: report) }
                }
                .animation(.spring(duration: 0.5, bounce: 0.3), value: model.awayReport)
            }
            .animation(.spring(duration: 0.4, bounce: 0.2), value: showJobs)
        }
        .background(FactoryBackdrop())
        .toolbar { toolbar }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter cards")
        .navigationTitle(model.selected?.name ?? "Ultra Code Factory")
        .navigationSubtitle(subtitle)
        .sheet(item: $openCard) { CardDetailView(card: $0) }
        .sheet(isPresented: Binding(get: { model.showingNewProject }, set: { model.showingNewProject = $0 })) {
            NewProjectWizard()
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .createWork(let project): CreateWorkSheet(project: project)
            case .newCard: NewCardSheet { openCard = $0 }
            }
        }
        .focusedSceneValue(\.boardActions, BoardActions(
            createWork: { if let p = model.selectedProject { sheet = .createWork(p) } },
            newCard: { sheet = .newCard },
            launch: { action in launch(action) },
            toggleJobs: { showJobs.toggle() },
            toggleAuto: {
                guard let id = model.selectedProject else { return }
                var mode = model.autoMode(for: id)
                mode.enabled.toggle()
                model.setAutoMode(mode, for: id)
            },
            enabled: model.hasProjects && model.selectedProject != nil
        ))
    }

    private var subtitle: String {
        guard model.hasProjects, model.selectedProject != nil else { return "" }
        let open = model.cards.filter { $0.status != .done && $0.status != .wontDo }.count
        return "\(open) open · \(model.cards.count) total"
    }

    @ViewBuilder
    private var detail: some View {
        if !model.hasProjects {
            WelcomeView()
        } else if let project = model.selectedProject {
            BoardView(project: project, search: search, kindFilter: kindFilter, openCard: $openCard)
        } else {
            ContentUnavailableView {
                Label("No projects yet", systemImage: "shippingbox")
            } description: {
                Text("Add a repository you already have, or start something brand new.")
            }
            .background(FactoryBackdrop())
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = model.errorMessage {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(message).font(.callout).lineLimit(3)
                Spacer()
                Button("Dismiss", systemImage: "xmark") { model.errorMessage = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .glassPanel(cornerRadius: 18, tint: .red)
            .padding(12)
            .shadow(color: .red.opacity(0.35), radius: 16)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: message) {
                try? await Task.sleep(for: .seconds(8))
                if model.errorMessage == message { model.errorMessage = nil }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        let enabled = model.hasProjects && model.selectedProject != nil
        ToolbarItem(placement: .primaryAction) {
            Button {
                if let p = model.selectedProject { sheet = .createWork(p) }
            } label: {
                Label("Create Work", systemImage: LaunchAction.create.symbol)
                    .labelStyle(.titleAndIcon)
            }
            .glassButton(prominent: true)
            .tint(Theme.safetyOrange)
            .help("Have an agent write a card from your idea (⌘N)")
            .disabled(!enabled)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("All Kinds") { kindFilter = nil }
                Divider()
                ForEach(model.kinds, id: \.self) { kind in
                    Button(kind) { kindFilter = kind }
                }
            } label: {
                Label(kindFilter ?? "Kind", systemImage: kindFilter == nil
                      ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
            .help("Filter by kind")
            .disabled(!enabled)

            Button("New Card", systemImage: "plus") { sheet = .newCard }
                .help("Write a card yourself (⇧⌘N)")
                .disabled(!enabled)

            Button("Triage", systemImage: LaunchAction.triage.symbol) { launch(.triage) }
                .help("Walk the backlog with an agent that asks you questions")
                .disabled(!enabled)

            RunWorkMenu { launch($0) }
                .disabled(!enabled)

            Button {
                showJobs.toggle()
            } label: {
                Label("Agents", systemImage: model.waitingJobs.isEmpty ? "gearshape.2" : "exclamationmark.bubble.fill")
            }
            .badge(model.activeJobs.count)
            .help("Show the factory floor (⌥⌘0)")
        }
    }

    private func launch(_ action: LaunchAction) {
        Task {
            let job: Job? = if action == .plan, let project = model.selected {
                await model.planBacklog(for: project)
            } else {
                await model.launch(action)
            }
            if let job {
                showJobs = true
                if action.isInteractive { openWindow(id: "console", value: job.id) }
            }
        }
    }
}

/// Lets the menu bar commands drive whichever board window is in front.
struct BoardActions {
    var createWork: () -> Void
    var newCard: () -> Void
    var launch: (LaunchAction) -> Void
    var toggleJobs: () -> Void
    var toggleAuto: () -> Void
    var enabled: Bool
}

extension FocusedValues {
    @Entry var boardActions: BoardActions?
}

/// "While you were away…": what the crew got done.
private struct AwayBanner: View {
    @Environment(FactoryModel.self) private var model
    let report: AwayReport

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: report.pullRequests > 0 ? "arrow.triangle.pull" : "cup.and.saucer.fill")
                .font(.title2)
                .foregroundStyle(Theme.safetyOrange)
                .symbolEffect(.bounce, options: .nonRepeating)
                .frame(width: 44, height: 44)
                .glassPanel(cornerRadius: 12, tint: Theme.safetyOrange)
            VStack(alignment: .leading, spacing: 3) {
                Text("While you were away · \(report.since.formatted(.relative(presentation: .named)))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(report.headline)
                    .font(.system(.headline, design: .rounded))
                if !report.details.isEmpty {
                    Text(report.details.joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Dismiss", systemImage: "xmark") { model.awayReport = nil }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .glassPanel(cornerRadius: 22)
        .frame(maxWidth: 620)
        .padding(12)
        .shadow(color: Theme.safetyOrange.opacity(0.25), radius: 20)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Run Work as a split button: click to work the next card, or open the
/// menu for Auto mode, its worker count, and dependency mapping.
private struct RunWorkMenu: View {
    @Environment(FactoryModel.self) private var model
    var launch: (LaunchAction) -> Void

    var body: some View {
        let id = model.selectedProject ?? ""
        let mode = model.autoMode(for: id)
        let busy = model.workers(for: id)
        Menu {
            Toggle(isOn: Binding(
                get: { mode.enabled },
                set: { var m = mode; m.enabled = $0; model.setAutoMode(m, for: id) }
            )) {
                Label("Auto Mode", systemImage: "bolt.fill")
            }
            Menu("Parallel Workers: \(mode.workers)") {
                ForEach(AutoMode.presets, id: \.self) { n in
                    Button {
                        model.setWorkerLimit(n, for: id)
                    } label: {
                        if n == mode.workers {
                            Label("\(n) worker\(n == 1 ? "" : "s")", systemImage: "checkmark")
                        } else {
                            Text("\(n) worker\(n == 1 ? "" : "s")")
                        }
                    }
                }
            }
            Text("Each worker builds a ready card on its own branch and opens a PR. Cards wait until what they depend on is Done.")
            Divider()
            Button("Run Next Card", systemImage: LaunchAction.work.symbol) { launch(.work) }
            Button("Map Dependencies", systemImage: LaunchAction.mapDependencies.symbol) { launch(.mapDependencies) }
        } label: {
            if mode.enabled {
                Label("Auto · \(busy.count)/\(mode.workers)", systemImage: "bolt.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Theme.safetyOrange)
            } else {
                Label("Run Work", systemImage: LaunchAction.work.symbol)
            }
        } primaryAction: {
            if mode.enabled {
                var m = mode
                m.enabled = false
                model.setAutoMode(m, for: id)
            } else {
                launch(.work)
            }
        }
        .help(mode.enabled
              ? "Auto mode is on: \(busy.count) of \(mode.workers) workers busy. Click to pause; the menu has more."
              : "Click to work the next card. Open the menu for Auto mode and parallel workers.")
    }
}
