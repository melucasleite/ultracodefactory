import CodeFactoryKit
import SwiftUI

struct CardDetailView: View {
    @Environment(FactoryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    let card: Card

    @State private var content: String?
    @State private var draft = ""
    @State private var editing = false
    @State private var error: String?
    @State private var status: CardStatus

    init(card: Card) {
        self.card = card
        _status = State(initialValue: card.status)
    }

    private var dirty: Bool { content != nil && draft != content }
    private var current: Card { var c = card; c.status = status; return c }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if let error {
                    ContentUnavailableView("Couldn’t open card", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if content == nil {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if editing {
                    TextEditor(text: $draft)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                } else {
                    ScrollView {
                        let (body, offset) = Self.renderable(draft)
                        MarkdownView(source: body) { line in
                            draft = MarkdownView.toggleTask(in: draft, line: line + offset)
                            save()
                        }
                        .padding(24)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 760, height: 680)
        .task { load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.color(for: status))
                .frame(width: 42, height: 42)
                .glassPanel(cornerRadius: 12, tint: Theme.color(for: status))
            VStack(alignment: .leading, spacing: 6) {
                Text(card.title).font(.system(.title2, design: .rounded).weight(.bold)).lineLimit(2)
                HStack(spacing: 8) {
                    if let id = card.cardID { Text("#\(id)").font(.caption.monospaced()).foregroundStyle(.secondary) }
                    if let kind = card.kind { KindChip(kind: kind) }
                    Text(card.file).font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Picker("Status", selection: $status) {
                ForEach(CardStatus.allCases) { s in
                    Label(s.title, systemImage: s.symbol).tag(s)
                }
            }
            .labelsHidden()
            .fixedSize()
            .onChange(of: status) { old, new in
                if dirty { save(as: old) }
                model.move(CardReference(project: card.project, status: old, file: card.file), to: new)
            }
            Picker("Mode", selection: $editing) {
                Label("Preview", systemImage: "eye").tag(false)
                Label("Edit", systemImage: "pencil").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .onChange(of: editing) { _, nowEditing in
                if !nowEditing, dirty { save() }
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Button("Reveal in Finder", systemImage: "folder") { Finder.reveal(model.cardURL(current)) }
            Button("Run Work", systemImage: "play.fill") {
                Task {
                    if let job = await model.launch(.work, project: card.project, text: card.file) {
                        openWindow(id: "console", value: job.id)
                    }
                }
            }
            Spacer()
            if dirty { Text("Edited").font(.caption).foregroundStyle(.secondary) }
            Button("Save") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!dirty)
            Button("Done") {
                if dirty { save() }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .glassButton(prominent: true)
            .tint(Theme.safetyOrange)
        }
        .labelStyle(.titleAndIcon)
        .padding(12)
    }

    private func load() {
        do {
            let text = try model.read(card)
            content = text
            draft = text
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save(as saveStatus: CardStatus? = nil) {
        var target = card
        target.status = saveStatus ?? status
        do {
            try model.save(target, content: draft)
            content = draft
        } catch {
            model.report(error)
        }
    }

    /// The part of the file worth previewing — frontmatter and HTML comments
    /// blanked out — plus how many lines were dropped from the top, so task
    /// toggles can be mapped back onto the file.
    static func renderable(_ source: String) -> (String, Int) {
        var text = source
        var offset = 0
        if let match = text.firstMatch(of: /\A---\r?\n(?:.*\r?\n)*?---\r?\n?/) {
            offset = text[match.range].filter { $0 == "\n" }.count
            text = String(text[match.range.upperBound...])
        }
        // Keep line numbers stable: replace each comment with as many newlines.
        text = text.replacing(/<!--[\s\S]*?-->/) { m in
            String(repeating: "\n", count: m.output.filter { $0 == "\n" }.count)
        }
        return (text, offset)
    }
}
