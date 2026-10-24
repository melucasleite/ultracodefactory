import CodeFactoryKit
import SwiftUI

/// Add an existing repository, or describe something brand new and let an
/// agent propose the starter backlog.
struct NewProjectWizard: View {
    @Environment(FactoryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Path { case existing, brandNew }
    enum Step: Int, CaseIterable {
        case idea, platforms, stack, features, design, location

        var title: String {
            switch self {
            case .idea: "What are you building?"
            case .platforms: "Where will it run?"
            case .stack: "What’s it built with?"
            case .features: "What should it do?"
            case .design: "How should it feel?"
            case .location: "Where should it live?"
            }
        }
    }

    @State private var path: Path?
    @State private var step: Step = .idea
    @State private var brief = ProjectBrief()
    @State private var customStack = ""
    @State private var customFeature = ""
    @State private var accent = Theme.safetyOrange
    @State private var useAccent = false
    @State private var parentFolder = WizardDefaults.parentFolder
    @State private var existingRepo: URL?
    @State private var planBacklog = true
    @State private var working = false
    @State private var error: String?
    @State private var suggesting = false
    @State private var suggested = false
    @State private var buildLog: [BuildStep] = []

    struct BuildStep: Identifiable, Equatable {
        let id: Int
        let label: String
        let symbol: String
        var done = false
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch path {
                case nil: chooser
                case .existing: existing
                case .brandNew: wizard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            Divider()
            footer.padding(16)
        }
        .frame(width: 680, height: 580)
        .overlay {
            if !buildLog.isEmpty { finale.transition(.opacity) }
        }
        .animation(.spring(duration: 0.35, bounce: 0.15), value: path)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: step)
    }

    // MARK: Step 0

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(title: "New Project", subtitle: "Bring a repo you have, or start from an idea.", symbol: "plus.rectangle.on.folder")
            HStack(spacing: 16) {
                choice(.existing, symbol: "folder.fill", title: "Existing project",
                       body: "Pick a repository on your Mac. Cards live in its .codefactory folder.")
                choice(.brandNew, symbol: "sparkles", title: "Brand new",
                       body: "Describe what you’re building and get a starter backlog to review.")
            }
            Spacer()
        }
    }

    private func choice(_ target: Path, symbol: String, title: String, body: String) -> some View {
        Button {
            path = target
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.safetyOrange)
                    .shadow(color: Theme.safetyOrange.opacity(0.6), radius: 10)
                Text(title).font(.system(.title3, design: .rounded).weight(.bold))
                Text(body).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .glassPanel(cornerRadius: 20, interactive: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: Existing

    private var existing: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(title: "Existing project", subtitle: "Code Factory keeps its cards in the repo, next to your code.", symbol: "folder.fill")
            HStack {
                Image(systemName: existingRepo == nil ? "questionmark.folder" : "checkmark.circle.fill")
                    .foregroundStyle(existingRepo == nil ? Color.secondary : Color.green)
                Text(existingRepo.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "No repository chosen")
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose Repository…") {
                    existingRepo = Finder.chooseFolder(message: "Choose your project’s repository") ?? existingRepo
                }
            }
            .padding(14)
            .glassPanel(cornerRadius: 14)
            Toggle(isOn: $planBacklog) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggest a backlog from the code")
                    Text("A headless agent reads the repo and proposes cards in Proposed. Nothing else changes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: Brand new

    private var wizard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.title).font(.system(.title2, design: .rounded).weight(.bold))
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Step.allCases, id: \.self) { s in
                        Capsule()
                            .fill(s.rawValue <= step.rawValue ? Theme.safetyOrange : Color.secondary.opacity(0.25))
                            .frame(width: s == step ? 22 : 8, height: 8)
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case .idea: ideaStep
                    case .platforms: platformsStep
                    case .stack: stackStep
                    case .features: featuresStep
                    case .design: designStep
                    case .location: locationStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step)
            }
            .scrollIndicators(.never)
        }
    }

    private var ideaStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Name", text: $brief.name, prompt: Text("Plant Pal"))
                .textFieldStyle(.plain)
                .font(.system(.title3, design: .rounded))
                .padding(12)
                .glassPanel(cornerRadius: 12)
            Text("Describe it like you’d pitch it to a friend.").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $brief.summary)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 160)
                .glassPanel(cornerRadius: 12)
            HStack(spacing: 12) {
                Button {
                    Task { await suggest() }
                } label: {
                    Label(suggesting ? "Thinking…" : "Suggest the rest from my pitch", systemImage: "sparkles")
                        .symbolEffect(.pulse, options: .repeat(.continuous), isActive: suggesting)
                }
                .glassButton()
                .tint(Theme.safetyOrange)
                .disabled(suggesting || brief.summary.trimmingCharacters(in: .whitespacesAndNewlines).count < 12
                          || model.prefs.claude == nil)
                if suggesting { ProgressView().controlSize(.small) }
                if suggested {
                    Label("Platforms, stack, features and style pre-filled. Tweak anything.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .animation(.spring, value: suggested)
        }
    }

    private func suggest() async {
        guard let claude = model.prefs.claude else { return }
        suggesting = true
        error = nil
        defer { suggesting = false }
        do {
            guard let s = try await BriefSuggester.suggest(
                name: brief.name, summary: brief.summary,
                platforms: WizardOptions.platforms.map(\.name),
                styles: WizardOptions.styles, appearances: WizardOptions.appearances,
                claude: claude
            ) else {
                error = "Couldn’t read a suggestion this time. Fill the steps in yourself, or try again."
                return
            }
            withAnimation(.spring) {
                if !s.platforms.isEmpty { brief.platforms = s.platforms }
                if !s.stack.isEmpty { brief.stack = s.stack }
                if !s.features.isEmpty { brief.features = s.features }
                brief.designStyle = s.designStyle ?? brief.designStyle
                brief.appearance = s.appearance ?? brief.appearance
                suggested = true
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var platformsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick everything that applies. The factory builds for all of them.").font(.callout).foregroundStyle(.secondary)
            ChipGrid(options: WizardOptions.platforms.map(\.name), symbols: WizardOptions.platforms.map(\.symbol),
                     selection: $brief.platforms)
        }
    }

    private var stackStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            let suggestions = WizardOptions.stacks(for: brief.platforms)
            Text(brief.platforms.isEmpty
                 ? "Choose platforms first for tailored suggestions, or name your own stack."
                 : "Suggestions for \(brief.platforms.joined(separator: ", ")). Leave everything off to let the agents choose.")
                .font(.callout).foregroundStyle(.secondary)
            ChipGrid(options: suggestions, selection: $brief.stack)
            AddRow(placeholder: "Something else, e.g. Phoenix LiveView", text: $customStack) {
                append(customStack, to: \.stack)
                customStack = ""
            }
            ChipGrid(options: brief.stack.filter { !suggestions.contains($0) }, selection: $brief.stack)
        }
    }

    private var featuresStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tap the common ones, then add what makes yours special.").font(.callout).foregroundStyle(.secondary)
            ChipGrid(options: WizardOptions.features, selection: $brief.features)
            AddRow(placeholder: "A feature in your own words", text: $customFeature) {
                append(customFeature, to: \.features)
                customFeature = ""
            }
            ChipGrid(options: brief.features.filter { !WizardOptions.features.contains($0) }, selection: $brief.features)
        }
    }

    private var designStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Style").font(.headline)
            ChipGrid(options: WizardOptions.styles, selection: single(\.designStyle))
            Text("Appearance").font(.headline)
            ChipGrid(options: WizardOptions.appearances, selection: single(\.appearance))
            HStack {
                Toggle("Accent colour", isOn: $useAccent)
                ColorPicker("Accent colour", selection: $accent, supportsOpacity: false)
                    .labelsHidden()
                    .disabled(!useAccent)
            }
            Text("Anything else? Inspirations, things to avoid…").font(.headline)
            TextEditor(text: $brief.notes)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 80)
                .glassPanel(cornerRadius: 12)
        }
    }

    private var locationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "folder.badge.plus").foregroundStyle(Theme.safetyOrange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Choose a folder")
                        .font(.body.monospaced()).lineLimit(1).truncationMode(.middle)
                    Text("A new folder with PROJECT.md, a .codefactory board and a fresh git repo.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Change…") {
                    if let url = Finder.chooseFolder(message: "Where should the project folder go?", startingAt: parentFolder?.path) {
                        parentFolder = url
                    }
                }
            }
            .padding(14)
            .glassPanel(cornerRadius: 14)
            Toggle(isOn: $planBacklog) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan a starter backlog now")
                    Text("A headless agent reads the brief and fills Proposed with 8–15 cards for you to review.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            GroupBox("PROJECT.md preview") {
                ScrollView {
                    Text(currentBrief.markdown)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 140)
            }
        }
    }

    // MARK: Finale

    private var finale: some View {
        ZStack {
            FactoryBackdrop()
            VStack(spacing: 22) {
                let allDone = buildLog.allSatisfy(\.done)
                Image(systemName: allDone ? "checkmark.seal.fill" : "gearshape.2.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(allDone ? Color.green : Theme.safetyOrange)
                    .shadow(color: (allDone ? Color.green : Theme.safetyOrange).opacity(0.7), radius: 20)
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !allDone)
                    .contentTransition(.symbolEffect(.replace))
                Text(allDone ? "Your factory is open" : "Building \(brief.name)…")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .contentTransition(.opacity)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(buildLog) { step in
                        HStack(spacing: 12) {
                            Image(systemName: step.done ? "checkmark.circle.fill" : step.symbol)
                                .foregroundStyle(step.done ? Color.green : Color.secondary)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 22)
                            Text(step.label).foregroundStyle(step.done ? .primary : .secondary)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(20)
                .frame(width: 360, alignment: .leading)
                .glassPanel(cornerRadius: 20)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.35), value: buildLog)
    }

    private func log(_ label: String, _ symbol: String) {
        buildLog.append(BuildStep(id: buildLog.count, label: label, symbol: symbol))
    }

    private func finishStep() async {
        if let index = buildLog.firstIndex(where: { !$0.done }) { buildLog[index].done = true }
        try? await Task.sleep(for: .milliseconds(380))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if path != nil {
                Button("Back", systemImage: "chevron.left") { back() }
                    .disabled(working)
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            if let path {
                Button {
                    Task { await primary(path) }
                } label: {
                    Label(primaryTitle(path), systemImage: primarySymbol(path))
                }
                .glassButton(prominent: true)
                .tint(Theme.safetyOrange)
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdvance(path) || working)
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private func primaryTitle(_ path: Path) -> String {
        switch path {
        case .existing: "Add Project"
        case .brandNew: step == .location ? "Create Project" : "Next"
        }
    }

    private func primarySymbol(_ path: Path) -> String {
        path == .brandNew && step != .location ? "chevron.right" : "hammer.fill"
    }

    private func canAdvance(_ path: Path) -> Bool {
        switch path {
        case .existing: existingRepo != nil
        case .brandNew:
            switch step {
            case .idea: !brief.name.trimmingCharacters(in: .whitespaces).isEmpty
                && CardBoard.slug(brief.name) != "card"
            case .platforms: !brief.platforms.isEmpty
            case .location: destination != nil
            default: true
            }
        }
    }

    private func back() {
        error = nil
        if path == .brandNew, let previous = Step(rawValue: step.rawValue - 1) {
            step = previous
        } else {
            path = nil
            step = .idea
        }
    }

    private func primary(_ path: Path) async {
        error = nil
        switch path {
        case .existing:
            guard let repo = existingRepo, let project = model.addProject(repository: repo) else { return }
            if planBacklog { await model.planBacklog(for: project, fromExistingCode: true) }
            dismiss()
        case .brandNew:
            if let next = Step(rawValue: step.rawValue + 1) {
                step = next
                return
            }
            guard let parentFolder else { return }
            working = true
            defer { working = false }
            do {
                log("Creating \(CardBoard.slug(brief.name))/", "folder")
                log("Writing the brief, PROJECT.md", "doc.text")
                log("Starting a git repository", "arrow.triangle.branch")
                log("Opening the board", "rectangle.split.3x1")
                if planBacklog { log("Planner clocking in", "list.bullet.clipboard") }
                let created = try await ProjectScaffold.create(in: parentFolder, brief: currentBrief)
                WizardDefaults.parentFolder = parentFolder
                for _ in 0..<3 { await finishStep() }
                guard let project = model.addProject(repository: created.repository) else {
                    buildLog = []
                    return
                }
                await finishStep()
                if planBacklog {
                    await model.planBacklog(for: project, fromExistingCode: false)
                    await finishStep()
                }
                try? await Task.sleep(for: .milliseconds(900))
                dismiss()
            } catch {
                buildLog = []
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: Helpers

    private var destination: URL? {
        parentFolder?.appending(path: CardBoard.slug(brief.name), directoryHint: .isDirectory)
    }

    private var currentBrief: ProjectBrief {
        var b = brief
        b.accentHex = useAccent ? accent.hexString : nil
        return b
    }

    private func append(_ raw: String, to keyPath: WritableKeyPath<ProjectBrief, [String]>) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !brief[keyPath: keyPath].contains(value) else { return }
        brief[keyPath: keyPath].append(value)
    }

    /// Adapts an optional single choice to the multi-select chip grid.
    private func single(_ keyPath: WritableKeyPath<ProjectBrief, String?>) -> Binding<[String]> {
        Binding(
            get: { brief[keyPath: keyPath].map { [$0] } ?? [] },
            set: { brief[keyPath: keyPath] = $0.last }
        )
    }
}

// MARK: - Options

enum WizardOptions {
    static let platforms: [(name: String, symbol: String)] = [
        ("Web app", "globe"),
        ("iOS", "iphone"),
        ("Android", "candybarphone"),
        ("Mac app", "macbook"),
        ("Windows & Linux desktop", "desktopcomputer"),
        ("Backend & API", "server.rack"),
        ("CLI tool", "terminal"),
    ]

    private static let stacksByPlatform: [String: [String]] = [
        "Web app": ["Next.js", "SvelteKit", "React Router", "Astro", "Rails", "Django"],
        "iOS": ["SwiftUI", "React Native (Expo)", "Flutter"],
        "Android": ["Kotlin + Jetpack Compose", "React Native (Expo)", "Flutter"],
        "Mac app": ["SwiftUI", "Tauri", "Electron"],
        "Windows & Linux desktop": ["Tauri", "Electron", "Flutter"],
        "Backend & API": ["Node + Hono", "FastAPI", "Go", "Rails", "Supabase", "PostgreSQL"],
        "CLI tool": ["Go", "Rust", "Node", "Python"],
    ]

    static func stacks(for platforms: [String]) -> [String] {
        var seen = Set<String>()
        let pool = platforms.isEmpty ? Self.platforms.map(\.name) : platforms
        return pool.flatMap { stacksByPlatform[$0] ?? [] }.filter { seen.insert($0).inserted }
    }

    static let features = [
        "Accounts & sign-in", "Payments & subscriptions", "Push notifications", "Offline support",
        "Real-time collaboration", "Search", "Admin dashboard", "Analytics", "AI assistant",
        "File uploads", "Sharing & invites", "Localization",
    ]

    static let styles = ["Minimal", "Apple-like glass", "Playful", "Bold & brutalist", "Clean corporate", "Retro"]
    static let appearances = ["Light and dark", "Dark first", "Light first"]
}

/// Remembers where brand-new projects go.
enum WizardDefaults {
    private static let key = "newProjectParent"

    static var parentFolder: URL? {
        get {
            if let path = UserDefaults.standard.string(forKey: key) { return URL(filePath: path, directoryHint: .isDirectory) }
            let home = FileManager.default.homeDirectoryForCurrentUser
            for candidate in ["Developer", "Projects", "projects", "Code", "code"] {
                let url = home.appending(path: candidate, directoryHint: .isDirectory)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
            return home
        }
        set { UserDefaults.standard.set(newValue?.path, forKey: key) }
    }
}

// MARK: - Chips

/// Toggleable glass chips that wrap onto as many lines as they need.
struct ChipGrid: View {
    let options: [String]
    var symbols: [String]? = nil
    @Binding var selection: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                let on = selection.contains(option)
                Button {
                    if on { selection.removeAll { $0 == option } } else { selection.append(option) }
                } label: {
                    HStack(spacing: 6) {
                        if let symbols { Image(systemName: symbols[index]) }
                        Text(option)
                        if on { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                    }
                    .font(.callout.weight(on ? .semibold : .regular))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .foregroundStyle(on ? Theme.safetyOrange : .primary)
                    .contentShape(Capsule())
                    .glassCapsule(tint: on ? Theme.safetyOrange : nil, interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct AddRow: View {
    let placeholder: String
    @Binding var text: String
    var add: () -> Void

    var body: some View {
        HStack {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit(add)
            Button("Add", systemImage: "plus.circle.fill", action: add)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.safetyOrange)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassCapsule()
    }
}

/// A simple left-to-right wrapping layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.items.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append(index)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

extension Color {
    /// `#RRGGBB` in sRGB.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .orange
        return String(format: "#%02X%02X%02X", Int(ns.redComponent * 255), Int(ns.greenComponent * 255), Int(ns.blueComponent * 255))
    }
}
