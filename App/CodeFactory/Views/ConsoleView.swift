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
    @State private var tab: Tab = .terminal
    @State private var follow = true
    @State private var expanded: Set<String> = []
    @State private var textWidth: CGFloat = 0

    enum Tab: String, CaseIterable { case terminal = "Terminal", activity = "Activity" }
    @State private var viewHeight: CGFloat = 0

    private func refit() {
        guard textWidth > 0, viewHeight > 0 else { return }
        let cells = TerminalMetrics.cells(fitting: CGSize(width: textWidth, height: viewHeight))
        console.fit(columns: cells.columns, rows: cells.rows)
    }

    init(jobID: String) {
        _console = State(initialValue: ConsoleModel(jobID: jobID))
    }

    var body: some View {
        Group {
            if let job = factory.job(console.jobID) {
                VStack(spacing: 0) {
                    header(job)
                    if tab == .terminal { terminal } else { activityView }
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
        .onAppear {
            console.job = factory.job(console.jobID)
            console.workingDirectory = console.job.flatMap { factory.project($0.projectID)?.repository }
            console.tmuxURL = factory.prefs.tmux
            console.start()
            refit()
        }
        .onChange(of: factory.job(console.jobID)) { _, job in console.job = job }
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
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Terminal mirrors the agent's screen. Activity lists every command, edit and output in full.")
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
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(console.screen)
                        .font(Font(TerminalMetrics.font))
                        .foregroundStyle(TerminalPalette.foreground)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(TerminalMetrics.padding)
                        // Measure the text area itself (inside the scroll view, so the
                        // scroller's gutter isn't counted) and fit the agent's terminal to it.
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                            textWidth = width
                            refit()
                        }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                viewHeight = height
                refit()
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

    /// Every step the agent took, in full: what it said, each command or
    /// edit, and the output, expandable.
    private var activityView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if console.activity.isEmpty {
                        Text("Waiting for the agent's first step…")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                    ForEach(console.activity) { step in
                        ActivityRow(step: step, expanded: isExpanded(step)) { toggle(step) }
                            .id(step.id)
                    }
                    Color.clear.frame(height: 1).id("activity-bottom")
                }
                .padding(12)
            }
            .background(TerminalPalette.background.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .bottomTrailing) {
                Toggle("Follow", isOn: $follow)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .padding(10)
                    .help("Keep the newest step in view")
            }
            .padding(.horizontal, 10)
            .environment(\.colorScheme, .dark)
            .onChange(of: console.activity.count) {
                if follow { proxy.scrollTo("activity-bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("activity-bottom", anchor: .bottom) }
        }
    }

    private func isExpanded(_ step: ActivityStep) -> Bool {
        expanded.contains(step.id) || step.isError || (step.isRunning && step.id == console.activity.last?.id)
    }

    private func toggle(_ step: ActivityStep) {
        if expanded.contains(step.id) { expanded.remove(step.id) } else { expanded.insert(step.id) }
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
                         ("⏎", .enter), ("esc", .escape), ("tab", .tab), ("⌃C", .interrupt), ("⌃O details", .details)], id: \.1) { label, key in
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

/// Character-cell geometry for the console's monospaced text.
@MainActor
enum TerminalMetrics {
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let padding: CGFloat = 12

    static let cellWidth: CGFloat = ("M" as NSString).size(withAttributes: [.font: font]).width
    static let lineHeight: CGFloat = NSLayoutManager().defaultLineHeight(for: font)

    static func cells(fitting size: CGSize) -> (columns: Int, rows: Int) {
        let columns = Int(((size.width - padding * 2) / cellWidth).rounded(.down))
        let rows = Int(((size.height - padding * 2) / lineHeight).rounded(.down))
        return (columns - 2, rows) // slack so rounding never wraps a full-width line
    }
}

/// One step in the Activity timeline.
private struct ActivityRow: View {
    let step: ActivityStep
    let expanded: Bool
    var toggle: () -> Void
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(step.kind == .said ? .callout : .system(size: 12, design: .monospaced))
                            .foregroundStyle(step.kind == .said ? Color.white.opacity(0.9) : TerminalPalette.foreground)
                            .lineLimit(expanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                        if let subtitle = step.subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if step.isRunning {
                        ProgressView().controlSize(.mini)
                    } else if let duration = step.duration, step.kind == .tool {
                        Text(Self.format(duration)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if step.kind == .tool, step.output?.isEmpty == false {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded, let output = step.output, !output.isEmpty {
                let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
                let shown = showAll ? lines[...] : lines.prefix(40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(shown.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(step.isError ? Color.red.opacity(0.9) : TerminalPalette.foreground.opacity(0.75))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if lines.count > 40 {
                        Button(showAll ? "Show less" : "Show all \(lines.count) lines") { showAll.toggle() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(step.isError ? Color.red.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private var icon: String {
        if step.kind == .said { return "text.bubble" }
        if step.isError { return "xmark.octagon.fill" }
        switch step.tool {
        case "Bash": return "terminal"
        case "Read": return "doc.text"
        case "Edit", "MultiEdit": return "pencil"
        case "Write": return "square.and.pencil"
        case "Grep", "Glob": return "magnifyingglass"
        case "Task", "Agent": return "person.2"
        case "WebFetch", "WebSearch": return "globe"
        case "TodoWrite": return "checklist"
        default: return "wrench.and.screwdriver"
        }
    }

    private var tint: Color {
        if step.isError { return .red }
        if step.kind == .said { return Theme.safetyOrange }
        return step.isRunning ? Theme.hazardYellow : Color.white.opacity(0.6)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        seconds < 1 ? "<1s" : seconds < 60 ? "\(Int(seconds))s" : "\(Int(seconds) / 60)m \(Int(seconds) % 60)s"
    }
}
