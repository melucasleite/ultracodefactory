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
                .frame(width: 128, height: 128)
                .shadow(color: Theme.safetyOrange.opacity(0.55), radius: 36)
                .phaseAnimator([0.0, 1.0]) { icon, phase in
                    icon.offset(y: phase * -6)
                } animation: { _ in .easeInOut(duration: 2.4) }
            VStack(spacing: 6) {
                Text("Code Factory")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.primary, Theme.safetyOrange], startPoint: .leading, endPoint: .trailing))
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
                .glassButton(prominent: true)
                .tint(Theme.safetyOrange)
                .controlSize(.extraLarge)

                Button {
                    do { try DemoFactory.install() } catch { model.report(error) }
                    model.configureVault()
                } label: {
                    Label("Try the Demo Factory", systemImage: "sparkles")
                        .frame(minWidth: 180)
                }
                .glassButton()
                .controlSize(.extraLarge)
            }
            ToolCheck()
            LayoutHint()
        }
        .padding(40)
        .glassPanel(cornerRadius: 32)
        .frame(maxWidth: 680)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FactoryBackdrop())
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
