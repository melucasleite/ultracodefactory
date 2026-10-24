import CodeFactoryKit
import SwiftUI

/// First-run screen: point the factory at a vault, or try the demo.
struct WelcomeView: View {
    @Environment(FactoryModel.self) private var model
    @AppStorage(Pref.vaultPath) private var vaultPath = ""
    @AppStorage(Pref.workFolder) private var workFolder = "Work"

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: Theme.safetyOrange.opacity(0.35), radius: 24)
            VStack(spacing: 6) {
                Text("Code Factory").font(.largeTitle.bold())
                Text("A kanban board for your markdown work cards, staffed by Claude Code agents.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if !vaultPath.isEmpty {
                Label("No “\(workFolder)” folder found in \(vaultPath)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            HStack(spacing: 12) {
                Button {
                    if let url = Finder.chooseFolder(message: "Choose the folder that contains your “\(workFolder)” folder", startingAt: vaultPath) {
                        vaultPath = url.path
                    }
                } label: {
                    Label("Choose Vault Folder…", systemImage: "folder")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.safetyOrange)
                .controlSize(.large)

                Button {
                    do { try DemoFactory.install() } catch { model.report(error) }
                    model.configureVault()
                } label: {
                    Label("Try the Demo Factory", systemImage: "sparkles")
                        .frame(minWidth: 180)
                }
                .controlSize(.large)
            }
            ToolCheck()
            LayoutHint()
        }
        .padding(40)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ToolCheck: View {
    var body: some View {
        let prefs = Preferences()
        HStack(spacing: 18) {
            tool("claude", found: prefs.claude)
            tool("tmux", found: prefs.tmux)
        }
        .font(.callout)
    }

    private func tool(_ name: String, found: URL?) -> some View {
        Label {
            Text(found.map { "\(name) — \($0.path)" } ?? "\(name) not found")
        } icon: {
            Image(systemName: found == nil ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(found == nil ? .red : .green)
        }
        .help(found == nil ? "Install it, or set its path in Settings → Agents" : "")
    }
}

private struct LayoutHint: View {
    var body: some View {
        GroupBox {
            Text("""
            vault/
            └─ Work/
               └─ my-project/
                  ├─ proposed/   todo/   picked-up/
                  └─ waiting/    done/   wont-do/   ← one .md card per file
            """)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Expected layout").font(.caption.weight(.semibold))
        }
    }
}
