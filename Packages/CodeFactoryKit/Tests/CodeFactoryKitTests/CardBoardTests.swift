import Foundation
import Testing
@testable import CodeFactoryKit

@Suite struct CardBoardTests {
    let root: URL
    let board: CardBoard

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "cf-tests-\(UUID().uuidString)")
        board = CardBoard(root: root, project: "p1")
        try board.prepare()
    }

    @Test(arguments: ["", "..", "../etc", "a/b", ".hidden", "a\\b", " padded", "nul\0byte"])
    func rejectsUnsafeSegments(_ name: String) {
        #expect(throws: CardError.self) { try CardBoard.segment(name) }
    }

    @Test func cardURLsStayInsideTheRoot() throws {
        #expect(throws: CardError.self) { try board.cardURL(status: .todo, file: "../x.md") }
        #expect(throws: CardError.self) { try board.cardURL(status: .todo, file: "notes.txt") }
        let url = try board.cardURL(status: .todo, file: "ok.md")
        #expect(url.path.hasPrefix(board.root.path))
    }

    @Test func prepareCreatesEveryStatusFolder() {
        for status in CardStatus.allCases {
            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: root.appending(path: status.rawValue).path, isDirectory: &isDir))
            #expect(isDir.boolValue)
        }
    }

    @Test func createListMoveRoundTrip() throws {
        let file = try board.create(title: "Build the Factory!", kind: "chore", status: .todo)
        #expect(file == "build-the-factory.md")

        var cards = board.listCards()
        #expect(cards.count == 1)
        #expect(cards[0].title == "Build the Factory!")
        #expect(cards[0].kind == "chore")
        #expect(cards[0].project == "p1")

        try board.move(file: file, from: .todo, to: .done)
        cards = board.listCards()
        #expect(cards.map(\.status) == [.done])
        #expect(try board.read(status: .done, file: file).contains("status: done"))
    }

    @Test func moveRefusesToOverwrite() throws {
        let file = try board.create(title: "Twin", status: .todo)
        try board.write(status: .done, file: file, content: "keep me")
        #expect(throws: CardError.alreadyExists(try board.cardURL(status: .done, file: file).path)) {
            try board.move(file: file, from: .todo, to: .done)
        }
        #expect(try board.read(status: .done, file: file) == "keep me")
    }

    @Test func duplicateTitlesGetDistinctFiles() throws {
        let a = try board.create(title: "Same")
        let b = try board.create(title: "Same")
        #expect(a != b)
    }

    @Test func slugs() {
        #expect(CardBoard.slug("Café — déjà vu!") == "cafe-deja-vu")
        #expect(CardBoard.slug("***") == "card")
    }
}

@Suite struct ProjectTests {
    @Test func cardsLiveInTheRepositoryByDefault() {
        let project = Project(repository: URL(filePath: "/tmp/my-app"))
        #expect(project.name == "my-app")
        #expect(project.cardsRoot.path == "/tmp/my-app/.codefactory")
        #expect(project.board.project == project.id)
    }

    @Test func cardsCanLiveElsewhere() {
        let project = Project(repository: URL(filePath: "/tmp/my-app"), cardsOverride: URL(filePath: "/tmp/vault/Work/my-app"))
        #expect(project.cardsRoot.path == "/tmp/vault/Work/my-app")
    }

    @Test func missingRepositoryIsReported() {
        let project = Project(repository: URL(filePath: "/nonexistent-\(UUID().uuidString)"))
        #expect(throws: CardError.self) { try project.validatedRepository() }
    }

    @Test func storeRoundTrip() throws {
        let store = ProjectStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "cf-projects-\(UUID().uuidString).json"))
        #expect(store.load().isEmpty)
        let projects = [
            Project(repository: URL(filePath: "/tmp/a")),
            Project(repository: URL(filePath: "/tmp/b"), cardsOverride: URL(filePath: "/tmp/cards")),
        ]
        try store.save(projects)
        #expect(store.load() == projects)
    }
}

@Suite struct PullRequestLinkTests {
    @Test func findsTheLastPullRequestLink() {
        let body = """
        Superseded: https://github.com/acme/app/pull/12
        Now: https://github.com/acme/app/pull/15.
        """
        let url = Card.pullRequestURL(in: body)
        #expect(url?.absoluteString == "https://github.com/acme/app/pull/15")
    }

    @Test func understandsGitLab() {
        #expect(Card.pullRequestURL(in: "see https://gitlab.com/acme/app/-/merge_requests/7")?.lastPathComponent == "7")
    }

    @Test func ignoresOtherLinks() {
        #expect(Card.pullRequestURL(in: "https://github.com/acme/app/issues/3") == nil)
    }

    @Test func boardSurfacesTheLink() throws {
        let board = CardBoard(root: FileManager.default.temporaryDirectory.appending(path: "cf-pr-\(UUID().uuidString)"), project: "p")
        try board.create(title: "Ship it", status: .waiting, body: "PR: https://github.com/acme/app/pull/42")
        #expect(board.listCards().first?.pullRequestNumber == "42")
    }
}

@Suite struct ExecutionOrderTests {
    let board: CardBoard

    init() throws {
        board = CardBoard(root: FileManager.default.temporaryDirectory.appending(path: "cf-order-\(UUID().uuidString)"), project: "p")
        try board.prepare()
        for (title, order) in [("Third", "3"), ("First", "1"), ("Second", "2")] {
            let file = try board.create(title: title, status: .todo)
            let content = try board.read(status: .todo, file: file)
            try board.write(status: .todo, file: file, content: Frontmatter.updating(content, with: ["order": order]))
        }
        try board.create(title: "Unordered", status: .todo)
    }

    @Test func sortsByOrderThenUnorderedLast() {
        #expect(board.listCards().map(\.title) == ["First", "Second", "Third", "Unordered"])
    }

    @Test func reorderMovesAndRenumbers() throws {
        try board.reorder(file: "third.md", in: .todo, before: ("first.md", .todo))
        #expect(board.listCards().map(\.title) == ["Third", "First", "Second", "Unordered"])
        #expect(board.listCards().map(\.order) == [1, 2, 3, 4])
        try board.reorder(file: "third.md", in: .todo, before: nil)
        #expect(board.listCards().map(\.title) == ["First", "Second", "Unordered", "Third"])
    }

    @Test func orderIsProjectWideAcrossColumns() throws {
        try board.move(file: "second.md", from: .todo, to: .pickedUp)
        // Moving keeps its number, so the plan's sequence survives.
        #expect(board.listCards().first { $0.file == "second.md" }?.order == 2)
        try board.reorder(file: "unordered.md", in: .todo, before: ("first.md", .todo))
        let byFile = Dictionary(uniqueKeysWithValues: board.listCards().map { ($0.file, $0.order) })
        #expect(byFile["unordered.md"] == 1)
        #expect(byFile["first.md"] == 2)
        #expect(byFile["second.md"] == 3)
        #expect(byFile["third.md"] == 4)
    }
}
