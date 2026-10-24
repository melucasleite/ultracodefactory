import CodeFactoryKit
import SwiftUI

struct SidebarView: View {
    @Environment(FactoryModel.self) private var model
    @State private var addingProject = false
    @State private var newProject = ""

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedProject) {
            Section("Projects") {
                ForEach(model.projects, id: \.self) { project in
                    ProjectRow(
                        name: project,
                        open: model.openCounts[project] ?? 0,
                        jobs: model.jobs(for: project).filter(\.state.isActive)
                    )
                    .tag(project)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) { floorStatus }
        .toolbar {
            ToolbarItem {
                Button("New Project", systemImage: "folder.badge.plus") { addingProject = true }
                    .disabled(!model.vaultReady)
            }
        }
        .alert("New Project", isPresented: $addingProject) {
            TextField("project-name", text: $newProject)
            Button("Create") {
                model.createProject(newProject.trimmingCharacters(in: .whitespaces))
                newProject = ""
            }
            Button("Cancel", role: .cancel) { newProject = "" }
        } message: {
            Text("Creates the status folders in your vault. Agents run in a repository with the same name inside your repositories folder.")
        }
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
    let name: String
    let open: Int
    let jobs: [Job]

    var body: some View {
        HStack {
            Label(name, systemImage: "shippingbox")
            Spacer()
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
