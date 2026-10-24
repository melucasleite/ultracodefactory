import CodeFactoryKit
import SwiftUI

@main
struct CodeFactoryApp: App {
    @State private var model = FactoryModel()

    var body: some Scene {
        Window("Ultra Code Factory", id: "board") {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 560)
        }
        .defaultSize(width: 1480, height: 900)
        .commands { FactoryCommands() }

        WindowGroup("Console", id: "console", for: String.self) { $jobID in
            if let jobID {
                ConsoleView(jobID: jobID).environment(model)
            }
        }
        .defaultSize(width: 980, height: 680)

        Settings {
            SettingsView()
        }

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            MenuBarLabel().environment(model)
        }
    }
}

struct FactoryCommands: Commands {
    @FocusedValue(\.boardActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Create Work…") { actions?.createWork() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions?.enabled != true)
            Button("New Card…") { actions?.newCard() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions?.enabled != true)
        }
        CommandMenu("Agents") {
            Group {
            Button("Run Work") { actions?.launch(.work) }
                .keyboardShortcut("r", modifiers: .command)
            Button("Triage") { actions?.launch(.triage) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Open Session in Repository") { actions?.launch(.session) }
            Button("Plan Backlog") { actions?.launch(.plan) }
            Button("Map Dependencies") { actions?.launch(.mapDependencies) }
            Divider()
            Button("Toggle Auto Mode") { actions?.toggleAuto() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Show Factory Floor") { actions?.toggleJobs() }
                .keyboardShortcut("0", modifiers: [.command, .option])
            }
            .disabled(actions?.enabled != true)
        }
    }
}
