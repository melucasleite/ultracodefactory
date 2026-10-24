import CodeFactoryKit
import SwiftUI

/// First-run screen: add a project, start a new one, or try the demo.
struct WelcomeView: View {
    @Environment(FactoryModel.self) private var model

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
                Text("Ultra Code Factory")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.primary, Theme.safetyOrange], startPoint: .leading, endPoint: .trailing))
                Text("Write the backlog. Grab a coffee. Come back to pull requests.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button {
                    model.showingNewProject = true
                } label: {
                    Label("New Project…", systemImage: "plus")
                        .frame(minWidth: 180)
                }
                .glassButton(prominent: true)
                .tint(Theme.safetyOrange)
                .controlSize(.extraLarge)

                Button {
                    do { model.addProject(repository: try DemoFactory.install()) } catch { model.report(error) }
                } label: {
                    Label("Try the Demo Factory", systemImage: "sparkles")
                        .frame(minWidth: 180)
                }
                .glassButton()
                .controlSize(.extraLarge)
            }
            Text("Or drop a repository folder onto the sidebar.")
                .font(.callout)
                .foregroundStyle(.secondary)
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
            my-app/                 ← your repository
            ├─ PROJECT.md           ← the brief agents read first
            └─ .codefactory/
               ├─ proposed/   todo/   picked-up/
               └─ waiting/    done/   wont-do/   ← one .md card per file
            """)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Cards live with your code").font(.caption.weight(.semibold))
        }
    }
}
