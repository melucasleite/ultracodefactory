import Foundation
import Testing
@testable import CodeFactoryKit

@Suite struct WorkSchedulerTests {
    func card(_ slug: String, _ status: CardStatus, order: Int, deps: [String] = []) -> Card {
        Card(project: "p", status: status, file: slug + ".md", title: slug, order: order, dependsOn: deps)
    }

    @Test func parsesDependencyLists() {
        #expect(Card.parseDependencies("a, b") == ["a", "b"])
        #expect(Card.parseDependencies("[a.md, 'b']") == ["a", "b"])
        #expect(Card.parseDependencies(nil) == [])
        #expect(Card.parseDependencies("[]") == [])
    }

    @Test func readyCardsRespectDependenciesOrderAndClaims() {
        let cards = [
            card("skeleton", .done, order: 1),
            card("protocol", .todo, order: 2, deps: ["skeleton"]),
            card("relay", .todo, order: 3, deps: ["protocol"]),
            card("ios-shell", .todo, order: 4, deps: ["skeleton"]),
            card("icons", .todo, order: 5),
            card("gone-dep", .todo, order: 6, deps: ["deleted-card"]),
        ]
        #expect(WorkScheduler.ready(in: cards).map(\.slug) == ["protocol", "ios-shell", "icons", "gone-dep"])
        #expect(WorkScheduler.ready(in: cards, excluding: ["protocol"]).map(\.slug) == ["ios-shell", "icons", "gone-dep"])
        #expect(WorkScheduler.blockers(of: cards[2], in: cards).map(\.slug) == ["protocol"])
    }

    @Test func waitingWorkersDontStallTheLine() {
        #expect(WorkScheduler.slotsToFill(limit: 3, running: 0, waiting: 0) == 3)
        #expect(WorkScheduler.slotsToFill(limit: 3, running: 1, waiting: 2) == 2)
        #expect(WorkScheduler.slotsToFill(limit: 3, running: 2, waiting: 4) == 0) // hard cap of 6
        #expect(WorkScheduler.slotsToFill(limit: 3, running: 3, waiting: 0) == 0)
    }

    @Test func boardReadsDependsOn() throws {
        let board = CardBoard(root: FileManager.default.temporaryDirectory.appending(path: "cf-deps-\(UUID().uuidString)"), project: "p")
        try board.prepare()
        let file = try board.create(title: "Relay", status: .todo)
        let content = try board.read(status: .todo, file: file)
        try board.write(status: .todo, file: file, content: Frontmatter.updating(content, with: ["depends_on": "[protocol, skeleton]"]))
        #expect(board.listCards().first?.dependsOn == ["protocol", "skeleton"])
    }
}

@Suite struct LoopGuardTests {
    func card(_ slug: String, _ status: CardStatus) -> Card {
        Card(project: "p", status: status, file: slug + ".md", title: slug, order: 1)
    }

    @Test func duplicateTodoCopyIsNeverReady() {
        let cards = [card("relay", .todo), card("relay", .done), card("icons", .todo)]
        #expect(WorkScheduler.ready(in: cards).map(\.slug) == ["icons"])
    }

    @Test func repeatedQuickFinishesMarkACardStuck() {
        func job(_ minutesAgo: Double) -> Job {
            var j = Job(id: UUID().uuidString, project: "p", projectID: "p", prompt: "x", action: "work", mode: .interactive, state: .completed)
            j.card = "relay"
            j.finishedAt = Date.now.addingTimeInterval(-minutesAgo * 60)
            return j
        }
        #expect(!WorkScheduler.isStuck("relay", jobs: [job(1)]))
        #expect(WorkScheduler.isStuck("relay", jobs: [job(1), job(3)]))
        #expect(!WorkScheduler.isStuck("relay", jobs: [job(1), job(30)]))
    }

    @Test func straysAreMergedIntoTheRealCard() throws {
        let board = CardBoard(root: FileManager.default.temporaryDirectory.appending(path: "cf-stray-\(UUID().uuidString)"), project: "p")
        try board.prepare()
        try board.create(title: "Relay", status: .done)
        try "## From ADR\n\nKeep this.".write(to: board.root.appending(path: "todo/relay.md"), atomically: true, encoding: .utf8)
        #expect(board.strays().count == 1)
        let touched = try board.tidyStrays()
        #expect(touched.count == 1)
        #expect(try board.read(status: .done, file: "relay.md").contains("Keep this."))
        #expect(!FileManager.default.fileExists(atPath: board.root.appending(path: "todo/relay.md").path))
        #expect(board.strays().isEmpty)
    }
}
