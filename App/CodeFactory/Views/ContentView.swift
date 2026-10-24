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
            detail
                .overlay(alignment: .top) { errorBanner }
        }
        .inspector(isPresented: $showJobs) {
            JobsInspector()
                .inspectorColumnWidth(min: 260, ideal: 310, max: 440)
        }
        .toolbar { toolbar }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter cards")
        .navigationTitle(model.selectedProject ?? "Code Factory")
        .navigationSubtitle(subtitle)
        .sheet(item: $openCard) { CardDetailView(card: $0) }
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
            enabled: model.vaultReady && model.selectedProject != nil
        ))
    }

    private var subtitle: String {
        guard model.vaultReady, model.selectedProject != nil else { return "" }
        let open = model.cards.filter { $0.status != .done && $0.status != .wontDo }.count
        return "\(open) open · \(model.cards.count) total"
    }

    @ViewBuilder
    private var detail: some View {
        if !model.vaultReady {
            WelcomeView()
        } else if let project = model.selectedProject {
            BoardView(project: project, search: search, kindFilter: kindFilter, openCard: $openCard)
        } else {
            ContentUnavailableView {
                Label("No projects yet", systemImage: "shippingbox")
            } description: {
                Text("Create a project folder in your vault’s work folder, or use **New Project** in the sidebar.")
            }
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = model.errorMessage {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white)
                Text(message).foregroundStyle(.white).font(.callout).lineLimit(3)
                Spacer()
                Button("Dismiss", systemImage: "xmark") { model.errorMessage = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 10))
            .padding(12)
            .shadow(radius: 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: message) {
                try? await Task.sleep(for: .seconds(8))
                if model.errorMessage == message { model.errorMessage = nil }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        let enabled = model.vaultReady && model.selectedProject != nil
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

            ControlGroup {
                Button("Triage", systemImage: LaunchAction.triage.symbol) { launch(.triage) }
                    .help("Walk the backlog with an agent that asks you questions")
                Button("Run Work", systemImage: LaunchAction.work.symbol) { launch(.work) }
                    .help("Start an agent on the next card")
            }
            .disabled(!enabled)

            Button {
                if let p = model.selectedProject { sheet = .createWork(p) }
            } label: {
                Label("Create Work", systemImage: LaunchAction.create.symbol)
            }
            .help("Have an agent write a card from your idea (⌘N)")
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
            if let job = await model.launch(action) {
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
    var enabled: Bool
}

extension FocusedValues {
    @Entry var boardActions: BoardActions?
}
