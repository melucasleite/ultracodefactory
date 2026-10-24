import CodeFactoryKit
import SwiftUI

/// A window onto one agent's terminal, with native controls for the
/// questions Claude asks.
struct ConsoleView: View {
    @Environment(FactoryModel.self) private var factory
    @State private var console: ConsoleModel
    @State private var message = ""
    @State private var copied = false
    @State private var confirmStop = false
    @FocusState private var terminalFocused: Bool

    init(jobID: String) {
        _console = State(initialValue: ConsoleModel(jobID: jobID))
    }

    var body: some View {
        Group {
            if let job = factory.job(console.jobID) {
                VStack(spacing: 0) {
                    header(job)
                    terminal
                    if let question = console.question, job.state.isActive {
                        QuestionPanel(question: question) { console.choose($0) } submit: { console.send(.enter) }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if console.canSend { keyBar }
                    composer(job)
                }
                .animation(.snappy, value: console.question)
            } else {
                ContentUnavailableView("Job not found", systemImage: "questionmark.folder",
                                       description: Text("It may have been cleared from the floor."))
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(FactoryBackdrop(animated: false))
        .onAppear { console.start(factory: factory) }
        .onDisappear { console.stop() }
    }

    private func header(_ job: Job) -> some View {
        HStack(spacing: 12) {
            StatusLight(color: Theme.color(for: job.state), pulsing: job.state.isActive)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.prompt).font(.headline).lineLimit(1)
                Text("\(job.project) · \(job.actionTitle) · \(job.state.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if job.state.isActive, let attach = job.attachCommand {
                Button {
                    Finder.copy(attach)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Label(copied ? "Copied" : attach, systemImage: copied ? "checkmark" : "terminal")
                        .font(.caption.monospaced())
                }
                .help("Copy a command that attaches your own terminal to this session")
            }
            if job.state.isActive {
                Button("Stop", systemImage: "stop.fill", role: .destructive) { confirmStop = true }
                    .confirmationDialog("Stop this agent?", isPresented: $confirmStop) {
                        Button("Stop", role: .destructive) { Task { await factory.stop(job) } }
                    }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassPanel(cornerRadius: 18)
        .padding([.horizontal, .top], 10)
        .padding(.bottom, 8)
    }

    private var terminal: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(console.screen)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(TerminalPalette.foreground)
                        .textSelection(.enabled)
                        .fixedSize()
                        .padding(12)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(TerminalPalette.background.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(terminalFocused ? Theme.safetyOrange.opacity(0.8) : Color.white.opacity(0.08),
                                  lineWidth: terminalFocused ? 1.5 : 0.5)
            }
            .shadow(color: terminalFocused ? Theme.safetyOrange.opacity(0.35) : .black.opacity(0.3), radius: 14)
            .padding(.horizontal, 10)
            .onChange(of: console.revision) { proxy.scrollTo("bottom", anchor: .bottom) }
            .focusable(console.canSend)
            .focused($terminalFocused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in handle(press) }
            .onTapGesture { terminalFocused = true }
            .environment(\.colorScheme, .dark)
        }
    }

    /// Physical keys go straight to the agent while the terminal has focus.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard console.canSend, !press.modifiers.contains(.command) else { return .ignored }
        if press.modifiers.contains(.control), press.key == KeyEquivalent("c") {
            console.send(.interrupt)
            return .handled
        }
        switch press.key {
        case .upArrow: console.send(.up)
        case .downArrow: console.send(.down)
        case .leftArrow: console.send(.left)
        case .rightArrow: console.send(.right)
        case .return: console.send(.enter)
        case .escape: console.send(.escape)
        case .tab: console.send(press.modifiers.contains(.shift) ? .backTab : .tab)
        case .delete: console.send(.backspace)
        default:
            guard !press.characters.isEmpty, !press.modifiers.contains(.control) else { return .ignored }
            console.type(press.characters)
        }
        return .handled
    }

    private var keyBar: some View {
        HStack(spacing: 6) {
            Text(terminalFocused ? "Typing goes to the agent" : "Click the terminal to type into it, or:")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                ForEach([("↑", NamedKey.up), ("↓", .down), ("←", .left), ("→", .right),
                         ("⏎", .enter), ("esc", .escape), ("tab", .tab), ("⌃C", .interrupt)], id: \.1) { label, key in
                    Button(label) { console.send(key) }
                        .font(.caption.monospaced())
                        .controlSize(.small)
                        .glassButton()
                }
            }
            .glassGroup(spacing: 4)
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private func composer(_ job: Job) -> some View {
        HStack(spacing: 8) {
            TextField(console.canSend ? "Message the agent — ⏎ sends (empty sends Enter)" : "This job isn’t interactive or has ended",
                      text: $message, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .lineLimit(1...6)
                .disabled(!console.canSend)
                .onSubmit(send)
            Button("Send", systemImage: "paperplane.fill", action: send)
                .glassButton(prominent: true)
                .tint(Theme.safetyOrange)
                .disabled(!console.canSend)
        }
        .padding(.leading, 6).padding(6)
        .glassPanel(cornerRadius: 22)
        .padding(10)
    }

    private func send() {
        console.submit(message)
        message = ""
    }
}

/// Claude's multiple-choice prompt, rendered as real buttons.
struct QuestionPanel: View {
    let question: PaneQuestion
    var choose: (Int) -> Void
    var submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(question.text, systemImage: "questionmark.bubble.fill")
                .font(.headline)
                .foregroundStyle(.primary)
                .symbolRenderingMode(.multicolor)
            VStack(spacing: 6) {
                ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                    Button {
                        choose(index)
                    } label: {
                        HStack(spacing: 10) {
                            if question.multiSelect {
                                Image(systemName: option.checked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(option.checked ? .green : .secondary)
                            }
                            Text("\(option.number)").font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(option.label).frame(maxWidth: .infinity, alignment: .leading)
                            if option.pointed {
                                Image(systemName: "arrowtriangle.left.fill").font(.caption2).foregroundStyle(Theme.safetyOrange)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .contentShape(Capsule())
                        .glassCapsule(tint: option.pointed ? Theme.safetyOrange : nil, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(option.number < 10 ? KeyboardShortcut(KeyEquivalent(Character("\(option.number)")), modifiers: .command) : nil)
                }
            }
            HStack {
                if question.multiSelect {
                    Button("Submit Selections", action: submit).glassButton(prominent: true).tint(Theme.safetyOrange)
                }
                Text("⌘1–⌘9 picks an option · or type your own answer below")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassPanel(cornerRadius: 20, tint: Theme.hazardYellow.opacity(0.4))
        .padding(.horizontal, 10).padding(.top, 10)
    }
}
