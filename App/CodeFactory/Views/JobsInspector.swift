import CodeFactoryKit
import SwiftUI

/// The factory floor: every agent, live ones first.
struct JobsInspector: View {
    @Environment(FactoryModel.self) private var model

    var body: some View {
        let active = model.jobs.filter(\.state.isActive)
        let finished = model.jobs.filter { !$0.state.isActive }
        VStack(spacing: 0) {
            HStack {
                Label("Factory Floor", systemImage: "gearshape.2.fill")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.safetyOrange)
                Spacer()
                if let id = model.selectedProject, model.autoMode(for: id).enabled {
                    let mode = model.autoMode(for: id)
                    HStack(spacing: 6) {
                        Button { model.setWorkerLimit(mode.workers - 1, for: id) } label: { Image(systemName: "minus") }
                            .disabled(mode.workers <= AutoMode.range.lowerBound)
                            .help("Fewer parallel workers")
                        Label("Auto \(model.workers(for: id).count)/\(mode.workers)", systemImage: "bolt.fill")
                            .monospacedDigit()
                        Button { model.setWorkerLimit(mode.workers + 1, for: id) } label: { Image(systemName: "plus") }
                            .disabled(mode.workers >= AutoMode.range.upperBound)
                            .help("More parallel workers")
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .glassCapsule(tint: Theme.safetyOrange)
                }
                if !active.isEmpty {
                    Text("\(active.count) live")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .glassCapsule(tint: Theme.safetyOrange)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            if model.jobs.isEmpty {
                ContentUnavailableView {
                    Label("Floor’s quiet", systemImage: "gearshape.2")
                } description: {
                    Text("Agents you start show up here. Try **Create Work** or **Run Work** in the toolbar.")
                }
            } else {
                List {
                    if !active.isEmpty {
                        Section("On the line") {
                            ForEach(active) { JobRow(job: $0) }
                        }
                    }
                    if !finished.isEmpty {
                        Section("Shipped") {
                            ForEach(finished) { JobRow(job: $0) }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                if !finished.isEmpty {
                    Divider()
                    HStack {
                        Spacer()
                        Button("Clear Finished", systemImage: "sparkles") { Task { await model.clearFinished() } }
                            .glassButton()
                    }
                    .padding(10)
                }
            }
        }
    }
}

struct JobRow: View {
    @Environment(FactoryModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let job: Job
    @State private var confirmStop = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(.clear).frame(width: 30, height: 30)
                    .glassCapsule(tint: Theme.color(for: job.state))
                    .shadow(color: Theme.color(for: job.state).opacity(job.state.isActive ? 0.6 : 0), radius: 8)
                Image(systemName: Theme.symbol(for: job.state))
                    .foregroundStyle(Theme.color(for: job.state))
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: job.state == .running)
                    .symbolEffect(.pulse, options: .repeat(.continuous), isActive: job.state == .waiting)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Label(job.actionTitle, systemImage: job.actionSymbol)
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                    Text("· \(job.project)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(job.prompt).font(.callout).lineLimit(2)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(stateLine).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                if job.neededPermission { permissionPanel }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openWindow(id: "console", value: job.id) }
        .contextMenu {
            Button("Open Console", systemImage: "terminal") { openWindow(id: "console", value: job.id) }
            if let attach = job.attachCommand {
                Button("Copy Attach Command", systemImage: "doc.on.doc") { Finder.copy(attach) }
            }
            if let log = job.logPath {
                Button("Reveal Log in Finder", systemImage: "folder") { Finder.reveal(URL(filePath: log)) }
            }
            if job.state.isActive {
                Divider()
                Button("Stop Agent…", systemImage: "stop.fill", role: .destructive) { confirmStop = true }
            }
        }
        .confirmationDialog("Stop this agent?", isPresented: $confirmStop) {
            Button("Stop", role: .destructive) { Task { await model.stop(job) } }
        } message: {
            Text("It will be interrupted mid-task. Work it already wrote to disk stays.")
        }
    }

    /// What the agent was refused, and the one-click way past it.
    private var permissionPanel: some View {
        let denials = job.summary?.denials ?? []
        let folders = model.foldersToAllow(for: job)
        return VStack(alignment: .leading, spacing: 6) {
            Label("Needed permission", systemImage: "lock.trianglebadge.exclamationmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.hazardYellow)
            ForEach(Array(denials.prefix(3).enumerated()), id: \.offset) { _, denial in
                Text("• " + denial.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if denials.count > 3 {
                Text("and \(denials.count - 3) more").font(.caption2).foregroundStyle(.tertiary)
            }
            if !folders.isEmpty {
                Button {
                    Task { await model.allowAndRerun(job) }
                } label: {
                    Label("Allow \(folders.map { ($0.path as NSString).abbreviatingWithTildeInPath }.joined(separator: ", ")) & Re-run",
                          systemImage: "lock.open.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                }
                .glassButton(prominent: true)
                .tint(Theme.safetyOrange)
                .help("Lets this project's agents read and write those folders from now on, then runs the job again")
            } else {
                Text("To allow commands like these, change the permission mode in Settings → Agents.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .glassPanel(cornerRadius: 10, tint: Theme.hazardYellow)
        .padding(.top, 4)
    }

    private var stateLine: String {
        switch job.state {
        case .running: "working · \(job.elapsed)"
        case .waiting: "waiting for you · \(job.elapsed)"
        case .completed:
            "finished in \(job.elapsed)" + (job.summary?.costUSD.map { String(format: " · $%.2f", $0) } ?? "")
        case .failed: "failed (exit \(job.exitCode ?? -1)) after \(job.elapsed)"
        case .stopped: "stopped after \(job.elapsed)"
        }
    }
}
