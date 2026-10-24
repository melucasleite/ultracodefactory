import Foundation

/// The things you can ask the factory to do for a project.
enum LaunchAction: String, CaseIterable, Identifiable {
    /// Headless: turn a one-line idea into a card.
    case create
    /// Interactive: pick up the next card and build it.
    case work
    /// Interactive: walk the backlog with you, asking questions.
    case triage
    /// Interactive: a plain Claude Code session in the repo.
    case session

    var id: String { rawValue }

    var title: String {
        switch self {
        case .create: "Create Work"
        case .work: "Run Work"
        case .triage: "Triage"
        case .session: "Open Session"
        }
    }

    var symbol: String {
        switch self {
        case .create: "wand.and.sparkles"
        case .work: "play.fill"
        case .triage: "scalemass"
        case .session: "terminal"
        }
    }

    var isInteractive: Bool { self != .create }
}
