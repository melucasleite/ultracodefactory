import CodeFactoryKit
import SwiftUI

struct SidebarView: View {
    @Environment(FactoryModel.self) private var model
    @State private var removing: Project?
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedProject) {
            Section("Projects") {
                ForEach(model.projects) { project in
                    ProjectRow(
                        project: project,
                        auto: model.autoMode(for: project.id).enabled,
                        open: model.openCounts[project.id] ?? 0,
                        jobs: model.jobs(for: project.id).filter(\.state.isActive)
                    )
                    .tag(project.id)
                    .contextMenu { menu(for: project) }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.safetyOrange, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .overlay(Label("Add as project", systemImage: "plus.circle.fill").foregroundStyle(Theme.safetyOrange))
                    .padding(8)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter { $0.hasDirectoryPath || (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            for folder in folders { model.addProject(repository: folder) }
            return !folders.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .safeAreaInset(edge: .bottom) { floorStatus }
        .toolbar {
            ToolbarItem {
                Button("New Project", systemImage: "plus") { model.showingNewProject = true }
                    .help("Add an existing repository or start a brand-new project")
            }
        }
        .confirmationDialog("Remove “\(removing?.name ?? "")” from Ultra Code Factory?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) {
                if let removing { model.removeProject(removing) }
            }
        } message: {
            Text("The repository and its cards stay on disk. You can add it back any time.")
        }
    }

    @ViewBuilder
    private func menu(for project: Project) -> some View {
        Button("Plan Backlog", systemImage: LaunchAction.plan.symbol) {
            Task { await model.planBacklog(for: project) }
        }
        Divider()
        Button("Reveal Repository in Finder", systemImage: "folder") { Finder.reveal(project.repository) }
        Button("Reveal Cards in Finder", systemImage: "tray.full") { Finder.reveal(project.cardsRoot) }
        Divider()
        Button("Locate Repository…", systemImage: "arrow.triangle.branch") {
            if let url = Finder.chooseFolder(message: "Choose the repository for “\(project.name)”", startingAt: project.repository.path) {
                var updated = project
                updated.repository = url.standardizedFileURL
                model.updateProject(updated)
            }
        }
        Button("Keep Cards in Another Folder…", systemImage: "externaldrive") {
            if let url = Finder.chooseFolder(message: "Choose a folder for “\(project.name)” cards, e.g. in your Obsidian vault", startingAt: project.cardsRoot.path) {
                var updated = project
                updated.cardsOverride = url.standardizedFileURL
                model.updateProject(updated)
            }
        }
        if project.cardsOverride != nil {
            Button("Keep Cards in the Repository", systemImage: "arrow.uturn.backward") {
                var updated = project
                updated.cardsOverride = nil
                model.updateProject(updated)
            }
        }
        Menu("Allowed Folders") {
            ForEach(project.allowedDirectories, id: \.self) { folder in
                Button("Stop Allowing \((folder.path as NSString).abbreviatingWithTildeInPath)") {
                    model.disallowFolder(folder, for: project)
                }
            }
            if !project.allowedDirectories.isEmpty { Divider() }
            Button("Allow a Folder…") {
                if let url = Finder.chooseFolder(message: "Let “\(project.name)” agents read and write this folder too, e.g. a reference project") {
                    model.allowFolder(url, for: project)
                }
            }
        }
        Divider()
        Button("Remove from Ultra Code Factory…", systemImage: "minus.circle", role: .destructive) { removing = project }
    }

    private var floorStatus: some View {
        let active = model.activeJobs.count
        let waiting = model.waitingJobs.count
        return HStack(spacing: 8) {
            StatusLight(color: waiting > 0 ? Theme.hazardYellow : active > 0 ? Theme.safetyOrange : .green,
                        pulsing: active > 0)
            Text(waiting > 0 ? "\(waiting) waiting for you" : active > 0 ? "\(active) agent\(active == 1 ? "" : "s") working" : "Floor idle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

private struct ProjectRow: View {
    let project: Project
    var auto = false
    let open: Int
    let jobs: [Job]

    var body: some View {
        HStack {
            Label(project.name, systemImage: "shippingbox")
                .help(project.repository.path)
            Spacer()
            if auto {
                Image(systemName: "bolt.fill").foregroundStyle(Theme.safetyOrange).help("Auto mode is on")
            }
            if jobs.contains(where: { $0.state == .waiting }) {
                Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(Theme.hazardYellow)
                    .help("An agent is waiting for your input")
            } else if !jobs.isEmpty {
                Image(systemName: "gearshape.2.fill")
                    .foregroundStyle(Theme.safetyOrange)
                    .symbolEffect(.rotate, options: .repeat(.continuous))
                    .help("\(jobs.count) agent(s) working")
            }
            if open > 0 {
                Text("\(open)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}
