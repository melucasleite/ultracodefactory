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
    /// The most recent pull request linked from the card body, if any.
    public var pullRequest: URL?

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
        priority: String? = nil,
        pullRequest: URL? = nil
    ) {
        self.project = project
        self.status = status
        self.file = file
        self.title = title
        self.cardID = cardID
        self.kind = kind
        self.updated = updated
        self.priority = priority
        self.pullRequest = pullRequest
    }

    /// The pull request number, for display ("#42").
    public var pullRequestNumber: String? {
        pullRequest.map(\.lastPathComponent)
    }

    /// Finds the last GitHub pull request or GitLab merge request URL in `text`.
    public static func pullRequestURL(in text: String) -> URL? {
        let pattern = /https:\/\/[A-Za-z0-9.-]+\/[A-Za-z0-9._\/-]+\/(?:pull|merge_requests)\/\d+/
        return text.matches(of: pattern).last.flatMap { URL(string: String($0.output)) }
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
