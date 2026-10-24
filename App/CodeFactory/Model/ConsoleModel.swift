import CodeFactoryKit
import Foundation
import Observation
import SwiftUI

/// Live view of one agent: mirrors its tmux pane (or tails its log) and
/// forwards your keystrokes back to it, in order.
@MainActor
@Observable
final class ConsoleModel {
    let jobID: String
    private(set) var screen = AttributedString()
    private(set) var plain = ""
    private(set) var question: PaneQuestion?
    private(set) var sessionEnded = false
    /// Bumped whenever the screen content changes, for auto-scroll.
    private(set) var revision = 0

    @ObservationIgnored private var raw = ""
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var sendChain: Task<Void, Never>?
    @ObservationIgnored private weak var factory: FactoryModel?
    @ObservationIgnored private var fittedSize: (columns: Int, rows: Int)?
    @ObservationIgnored private var fitTask: Task<Void, Never>?

    init(jobID: String) {
        self.jobID = jobID
    }

    var job: Job? { factory?.job(jobID) }

    func start(factory: FactoryModel) {
        self.factory = factory
        revision &+= 1 // re-render now that the job can be resolved
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private var tmux: Tmux? { factory?.prefs.tmux.map(Tmux.init) }

    private func poll() async {
        guard let job else { return }
        var next: String
        switch job.mode {
        case .interactive:
            guard let session = job.session, let tmux else { return }
            do {
                next = try await tmux.capture(session, history: 400, escapes: true)
                sessionEnded = false
            } catch {
                sessionEnded = true
                next = raw.isEmpty ? "(the session has ended)" : raw
            }
        case .headless:
            next = Self.tail(job.logPath, bytes: 96 * 1024) ?? "(waiting for output…)"
            sessionEnded = !job.state.isActive
        }
        if sessionEnded || !job.state.isActive { question = nil }
        guard next != raw else { return }
        raw = next
        let runs = ANSIParser.parse(next)
        plain = runs.map(\.text).joined()
        screen = TerminalPalette.attributed(runs)
        question = (job.mode == .interactive && !sessionEnded && !plain.contains(JobStore.busyMarker))
            ? QuestionParser.parse(Self.lastScreenful(plain)) : nil
        revision &+= 1
    }

    // MARK: Size

    /// Resizes the agent's tmux window to the console's size in character
    /// cells, so its TUI redraws to fit instead of scrolling sideways.
    /// Debounced, and skipped when nothing changed.
    func fit(columns: Int, rows: Int) {
        guard job?.mode == .interactive, let session = job?.session, let tmux else { return }
        guard columns >= 20, rows >= 5 else { return }
        if let fittedSize, fittedSize.columns == columns, fittedSize.rows == rows { return }
        fitTask?.cancel()
        fitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            try? await tmux.resize(session, columns: columns, rows: rows)
            self?.fittedSize = (columns, rows)
            try? await Task.sleep(for: .milliseconds(200))
            await self?.poll()
        }
    }

    // MARK: Input

    var canSend: Bool { job?.mode == .interactive && !sessionEnded && (job?.state.isActive ?? false) }

    func send(_ key: NamedKey) { enqueue { tmux, session in try await tmux.send(key, to: session) } }

    func type(_ text: String) { enqueue { tmux, session in try await tmux.type(text, to: session) } }

    /// Types a full message and presses Enter. An empty message is just Enter.
    func submit(_ text: String) {
        enqueue { tmux, session in
            try await tmux.type(text, to: session)
            try await tmux.send(.enter, to: session)
        }
    }

    /// Steers the TUI cursor to the option and picks it.
    func choose(_ index: Int) {
        guard let question else { return }
        let keys = question.keys(toChoose: index)
        self.question = nil
        enqueue { tmux, session in
            for key in keys { try await tmux.send(key, to: session) }
        }
    }

    /// Keystrokes go out strictly in order, each after the previous finished.
    private func enqueue(_ work: @escaping @Sendable (Tmux, String) async throws -> Void) {
        guard canSend, let tmux, let session = job?.session else { return }
        let previous = sendChain
        sendChain = Task { [weak self] in
            await previous?.value
            try? await work(tmux, session)
            try? await Task.sleep(for: .milliseconds(120))
            await self?.poll()
        }
    }

    // MARK: Helpers

    /// Only the bottom of the pane can hold the live widget; ignore scrollback.
    static func lastScreenful(_ text: String, lines: Int = 50) -> String {
        text.components(separatedBy: "\n").suffix(lines).joined(separator: "\n")
    }

    static func tail(_ path: String?, bytes: Int) -> String? {
        guard let path, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        return text.isEmpty ? nil : text
    }
}

/// Maps terminal colours onto a dark console palette.
enum TerminalPalette {
    static let background = Color(red: 0.07, green: 0.075, blue: 0.085)
    static let foreground = Color(red: 0.86, green: 0.87, blue: 0.88)

    private static let base: [(Double, Double, Double)] = [
        (0.16, 0.17, 0.19), (0.92, 0.33, 0.33), (0.45, 0.82, 0.45), (0.95, 0.77, 0.30),
        (0.38, 0.60, 0.98), (0.78, 0.47, 0.92), (0.33, 0.80, 0.86), (0.82, 0.83, 0.85),
        (0.42, 0.44, 0.47), (1.00, 0.47, 0.45), (0.58, 0.92, 0.55), (1.00, 0.86, 0.42),
        (0.55, 0.72, 1.00), (0.88, 0.62, 1.00), (0.50, 0.90, 0.95), (0.98, 0.98, 0.98),
    ]

    static func color(_ c: TerminalColor) -> Color {
        switch c {
        case .indexed(let i):
            let (r, g, b) = base[Int(i) % 16]
            return Color(red: r, green: g, blue: b)
        case .palette(let n):
            if n < 16 { return color(.indexed(n)) }
            if n >= 232 {
                let level = (Double(n) - 232) * 10 + 8
                return Color(red: level / 255, green: level / 255, blue: level / 255)
            }
            let i = Int(n) - 16
            func step(_ v: Int) -> Double { v == 0 ? 0 : (Double(v) * 40 + 55) / 255 }
            return Color(red: step(i / 36), green: step((i / 6) % 6), blue: step(i % 6))
        case .rgb(let r, let g, let b):
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
    }

    static func attributed(_ runs: [TerminalRun]) -> AttributedString {
        var out = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            var fg = run.style.foreground.map(color) ?? foreground
            var bg = run.style.background.map(color)
            if run.style.inverse {
                let swapped = bg ?? background
                bg = fg
                fg = swapped
            }
            piece.foregroundColor = run.style.dim ? fg.opacity(0.6) : fg
            if let bg { piece.backgroundColor = bg }
            if run.style.bold || run.style.italic {
                var font = Font.system(size: 12, weight: run.style.bold ? .bold : .regular, design: .monospaced)
                if run.style.italic { font = font.italic() }
                piece.font = font
            }
            if run.style.underline { piece.underlineStyle = .single }
            if run.style.strikethrough { piece.strikethroughStyle = .single }
            out += piece
        }
        return out
    }
}
