import Foundation
import Testing
@testable import CodeFactoryKit

@Suite struct GitHubTests {
    @Test func decodesGhOutput() throws {
        let json = #"{"baseRefName":"main","headRefName":"codefactory/relay","mergeStateStatus":"DIRTY","mergeable":"CONFLICTING","number":15,"state":"OPEN"}"#
        let pr = try #require(PullRequestStatus.decode(json))
        #expect(pr.number == 15)
        #expect(pr.hasConflicts)
        #expect(!pr.isMerged)
        #expect(!pr.isUndecided)
    }

    @Test func mergedAndUnknownStates() throws {
        let merged = try #require(PullRequestStatus.decode(#"{"baseRefName":"main","headRefName":"x","mergeStateStatus":"UNKNOWN","mergeable":"UNKNOWN","number":1,"state":"MERGED"}"#))
        #expect(merged.isMerged && !merged.hasConflicts && !merged.isUndecided)
        let unknown = try #require(PullRequestStatus.decode(#"{"baseRefName":"main","headRefName":"x","mergeStateStatus":"UNKNOWN","mergeable":"UNKNOWN","number":2,"state":"OPEN"}"#))
        #expect(unknown.isUndecided && !unknown.hasConflicts)
    }

    @Test func fixerPromptStaysInScope() {
        let p = AgentPrompts.fixConflicts(card: "relay", pullRequest: 15, branch: "codefactory/relay", base: "main",
                                          cardsFolder: URL(filePath: "/tmp/app/.codefactory"))
        #expect(p.contains("git merge origin/main"))
        #expect(p.contains("Don't change what the card is about"))
    }
}
