import Foundation

/// A work card as listed on the board — enough to draw a tile.
public struct Card: Identifiable, Hashable, Codable, Sendable {
    public var project: String
    public var status: CardStatus
    public var file: String
    public var title: String
    public var cardID: String?
    public var kind: String?
    public var updated: String?
    public var priority: String?

    /// Stable identity across a single listing: status folder plus filename.
    public var id: String { "\(project)/\(status.rawValue)/\(file)" }

    public init(
        project: String,
        status: CardStatus,
        file: String,
        title: String,
        cardID: String? = nil,
        kind: String? = nil,
        updated: String? = nil,
        priority: String? = nil
    ) {
        self.project = project
        self.status = status
        self.file = file
        self.title = title
        self.cardID = cardID
        self.kind = kind
        self.updated = updated
        self.priority = priority
    }
}

/// A card reference small enough to drag between columns.
public struct CardReference: Codable, Hashable, Sendable {
    public var project: String
    public var status: CardStatus
    public var file: String

    public init(project: String, status: CardStatus, file: String) {
        self.project = project
        self.status = status
        self.file = file
    }

    public init(_ card: Card) {
        self.init(project: card.project, status: card.status, file: card.file)
    }
}
