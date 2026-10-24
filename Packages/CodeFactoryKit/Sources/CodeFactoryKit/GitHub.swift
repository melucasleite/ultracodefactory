import Foundation

/// A pull request as `gh pr view --json` reports it.
public struct PullRequestStatus: Codable, Hashable, Sendable {
    public var number: Int
    public var state: String            // OPEN, MERGED, CLOSED
    public var mergeable: String        // MERGEABLE, CONFLICTING, UNKNOWN
    public var mergeStateStatus: String // CLEAN, DIRTY, BLOCKED, BEHIND, UNKNOWN…
    public var headRefName: String
    public var baseRefName: String

    public var isMerged: Bool { state == "MERGED" }
    public var isOpen: Bool { state == "OPEN" }
    public var hasConflicts: Bool { isOpen && (mergeable == "CONFLICTING" || mergeStateStatus == "DIRTY") }
    /// GitHub computes mergeability lazily; ask again shortly.
    public var isUndecided: Bool { isOpen && mergeable == "UNKNOWN" }

    public static func decode(_ json: String) -> PullRequestStatus? {
        try? JSONDecoder().decode(PullRequestStatus.self, from: Data(json.utf8))
    }
}

/// Talks to GitHub through the `gh` CLI, using your existing login.
public enum GitHub {
    public static let fields = "number,state,mergeable,mergeStateStatus,headRefName,baseRefName"

    public static func status(of pullRequest: URL, gh: URL) async throws -> PullRequestStatus? {
        let result = try await ProcessRunner.run(gh, ["pr", "view", pullRequest.absoluteString, "--json", fields])
        return PullRequestStatus.decode(result.stdout)
    }
}
