import CodeFactoryKit
import SwiftUI

/// Hand an idea to a headless agent and let it write the card.
struct CreateWorkSheet: View {
    @Environment(FactoryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var project: String
    @State private var idea = ""
    @State private var firing = false

    init(project: String) {
        _project = State(initialValue: project)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Create Work", subtitle: "A headless agent turns your idea into a card in To-Do.", symbol: "wand.and.sparkles")
            Picker("Project", selection: $project) {
                ForEach(model.projects) { Text($0.name).tag($0.id) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("What needs doing?").font(.callout.weight(.medium))
                TextEditor(text: $idea)
                    .font(.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            }
            Text("Runs `\(model.prompt(for: .create, text: "…"))` in **\(model.project(project)?.name ?? "the project")** with permission mode *\(model.prefs.permissionMode.title.lowercased())*.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    firing = true
                    Task {
                        if await model.launch(.create, project: project, text: idea) != nil { dismiss() }
                        firing = false
                    }
                } label: {
                    Label(firing ? "Starting…" : "Fabricate", systemImage: "hammer.fill")
                }
                .glassButton(prominent: true)
                .tint(Theme.safetyOrange)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || firing)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

/// Write a card yourself, no agent required.
struct NewCardSheet: View {
    @Environment(FactoryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind = "feature"
    @State private var status: CardStatus = .proposed
    var onCreated: (Card) -> Void

    private let kinds = ["feature", "bug", "chore", "refactor", "spike", "docs"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "New Card", subtitle: "Adds a markdown card to \(model.selected?.name ?? "the project").", symbol: "plus.rectangle.on.rectangle")
            Form {
                TextField("Title", text: $title, prompt: Text("Make the build faster"))
                Picker("Kind", selection: $kind) {
                    ForEach(kinds, id: \.self) { Text($0).tag($0) }
                }
                Picker("Column", selection: $status) {
                    ForEach(CardStatus.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    if let card = model.createCard(title: title.trimmingCharacters(in: .whitespaces), kind: kind, status: status) {
                        dismiss()
                        onCreated(card)
                    }
                }
                .glassButton(prominent: true)
                .tint(Theme.safetyOrange)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

struct SheetHeader: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.safetyOrange)
                .frame(width: 44, height: 44)
                .glassPanel(cornerRadius: 12, tint: Theme.safetyOrange)
                .shadow(color: Theme.safetyOrange.opacity(0.4), radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.title3, design: .rounded).weight(.bold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
