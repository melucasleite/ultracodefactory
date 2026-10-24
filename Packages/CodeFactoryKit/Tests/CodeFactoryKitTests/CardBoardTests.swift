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
