import CodeFactoryKit
import SwiftUI

/// The factory at a glance from the menu bar.
struct MenuBarView: View {
    @Environment(FactoryModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let active = model.activeJobs
        if active.isEmpty {
            Text("No agents working")
        } else {
            ForEach(active) { job in
                Button {
                    NSApp.activate()
                    openWindow(id: "console", value: job.id)
                } label: {
                    Text("\(job.state == .waiting ? "⚠︎ " : "⚙︎ ")\(job.project): \(job.prompt)")
                }
            }
        }
        Divider()
        Button("Open Ultra Code Factory") {
            NSApp.activate()
            openWindow(id: "board")
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct MenuBarLabel: View {
    @Environment(FactoryModel.self) private var model

    var body: some View {
        let active = model.activeJobs.count
        let waiting = model.waitingJobs.count
        if waiting > 0 {
            Label("\(waiting)", systemImage: "exclamationmark.bubble.fill")
        } else if active > 0 {
            Label("\(active)", systemImage: "gearshape.2.fill")
        } else {
            Image(systemName: "gearshape.2")
        }
    }
}
