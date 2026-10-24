import Foundation

/// The lifecycle columns of the board. Each status is a folder on disk, and a
/// card's location — not its frontmatter — is the source of truth.
public enum CardStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case proposed
    case todo
    case pickedUp = "picked-up"
    case waiting
    case done
    case wontDo = "wont-do"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .proposed: "Proposed"
        case .todo: "To-Do"
        case .pickedUp: "Picked Up"
        case .waiting: "Waiting"
        case .done: "Done"
        case .wontDo: "Won't Do"
        }
    }

    /// SF Symbol name for the column header.
    public var symbol: String {
        switch self {
        case .proposed: "lightbulb"
        case .todo: "tray.full"
        case .pickedUp: "hammer"
        case .waiting: "hourglass"
        case .done: "checkmark.seal"
        case .wontDo: "xmark.bin"
        }
    }
}
