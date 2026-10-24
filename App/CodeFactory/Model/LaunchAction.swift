import CodeFactoryKit
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
    /// Headless: propose a starter backlog with the built-in planner prompt.
    case plan
    /// Headless: fill in `depends_on:` across the board so work can run in parallel.
    case mapDependencies
    /// Interactive: resolve a pull request's merge conflicts in its worktree.
    case fixConflicts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .create: "Create Work"
        case .work: "Run Work"
        case .triage: "Triage"
        case .session: "Open Session"
        case .plan: "Plan Backlog"
        case .mapDependencies: "Map Dependencies"
        case .fixConflicts: "Fix Conflicts"
        }
    }

    var symbol: String {
        switch self {
        case .create: "wand.and.sparkles"
        case .work: "play.fill"
        case .triage: "scalemass"
        case .session: "terminal"
        case .plan: "list.bullet.clipboard"
        case .mapDependencies: "point.3.connected.trianglepath.dotted"
        case .fixConflicts: "arrow.triangle.merge"
        }
    }

    var isInteractive: Bool { self != .create && self != .plan && self != .mapDependencies }

    /// The column where this action's not-yet-written cards appear.
    var fabricatesInto: CardStatus? {
        switch self {
        case .create: .todo
        case .plan: .proposed
        default: nil
        }
    }
}
