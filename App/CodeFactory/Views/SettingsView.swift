import CodeFactoryKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Agents", systemImage: "gearshape.2") { AgentSettings() }
            Tab("General", systemImage: "bell") { GeneralSettings() }
        }
        .frame(width: 560)
        .scenePadding()
    }
}

private struct AgentSettings: View {
    @AppStorage(Pref.claudePath) private var claudePath = ""
    @AppStorage(Pref.tmuxPath) private var tmuxPath = ""
    @AppStorage(Pref.createCommand) private var createCommand = "/work-create"
    @AppStorage(Pref.workCommand) private var workCommand = "/work"
    @AppStorage(Pref.triageCommand) private var triageCommand = "/work-triage"
    @AppStorage(Pref.permissionMode) private var permissionMode = PermissionMode.acceptEdits.rawValue

    var body: some View {
        Form {
            Section("Tools") {
                BinaryField(name: "claude", path: $claudePath)
                BinaryField(name: "tmux", path: $tmuxPath)
            }
            Section {
                Picker("Permission mode", selection: $permissionMode) {
                    ForEach(PermissionMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                if PermissionMode(rawValue: permissionMode)?.isDangerous == true {
                    Label {
                        Text("Agents will run any command without asking — including deleting files or pushing code. Only use this in repositories you can afford to lose, ideally inside a container or VM.")
                    } icon: {
                        Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                    }
                    .font(.callout)
                }
            } header: {
                Text("Safety")
            } footer: {
                Text("Passed to Claude Code as `--permission-mode`. Headless agents can’t answer permission prompts, so actions outside the mode are refused.")
            }
            Section {
                TextField("Create Work", text: $createCommand, prompt: Text("/work-create"))
                TextField("Run Work", text: $workCommand, prompt: Text("/work"))
                TextField("Triage", text: $triageCommand, prompt: Text("/work-triage"))
            } header: {
                Text("Slash commands")
            } footer: {
                Text("The first message each agent receives. Example skills ship in the repository’s *Examples/skills* folder.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Pref.notifications) private var notifications = true

    var body: some View {
        Form {
            Section {
                Toggle("Notify me when an agent needs input or finishes", isOn: $notifications)
            }
            Section("Data") {
                LabeledContent("Job ledger and logs") {
                    Button("Show in Finder") { Finder.open(Preferences.supportDirectory) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct BinaryField: View {
    let name: String
    @Binding var path: String

    var body: some View {
        let found = BinaryLocator.locate(name, override: path)
        LabeledContent {
            HStack {
                TextField(name, text: $path, prompt: Text("Auto-detect"))
                    .labelsHidden()
                Button("Choose…") {
                    if let url = Finder.chooseExecutable(message: "Locate the \(name) executable") { path = url.path }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: found == nil ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(found == nil ? .red : .green)
                VStack(alignment: .leading) {
                    Text(name).font(.body.monospaced())
                    Text(found?.path ?? "not found").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
