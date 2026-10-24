import Foundation
import Testing
@testable import CodeFactoryKit

@Suite struct VaultTests {
    let root: URL
    let vault: Vault

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "cf-tests-\(UUID().uuidString)")
        vault = Vault(vaultRoot: root, workFolder: "Work")
        try vault.createProject("alpha")
    }

    @Test(arguments: ["", "..", "../etc", "a/b", ".hidden", "a\\b", " padded", "nul\0byte"])
    func rejectsUnsafeSegments(_ name: String) {
        #expect(throws: VaultError.self) { try Vault.segment(name) }
    }

    @Test func cardURLsStayInsideTheWorkRoot() throws {
        #expect(throws: VaultError.self) { try vault.cardURL(project: "..", status: .todo, file: "x.md") }
        #expect(throws: VaultError.self) { try vault.cardURL(project: "alpha", status: .todo, file: "../x.md") }
        #expect(throws: VaultError.self) { try vault.cardURL(project: "alpha", status: .todo, file: "notes.txt") }
        let url = try vault.cardURL(project: "alpha", status: .todo, file: "ok.md")
        #expect(url.path.hasPrefix(vault.workRoot.path))
    }

    @Test func createListMoveRoundTrip() throws {
        let file = try vault.create(project: "alpha", title: "Build the Factory!", kind: "chore", status: .todo)
        #expect(file == "build-the-factory.md")
        #expect(try vault.listProjects() == ["alpha"])

        var cards = try vault.listCards(project: "alpha")
        #expect(cards.count == 1)
        #expect(cards[0].title == "Build the Factory!")
        #expect(cards[0].kind == "chore")

        try vault.move(project: "alpha", file: file, from: .todo, to: .done)
        cards = try vault.listCards(project: "alpha")
        #expect(cards.map(\.status) == [.done])
        #expect(try vault.read(project: "alpha", status: .done, file: file).contains("status: done"))
    }

    @Test func moveRefusesToOverwrite() throws {
        let file = try vault.create(project: "alpha", title: "Twin", status: .todo)
        try vault.write(project: "alpha", status: .done, file: file, content: "keep me")
        #expect(throws: VaultError.alreadyExists(try vault.cardURL(project: "alpha", status: .done, file: file).path)) {
            try vault.move(project: "alpha", file: file, from: .todo, to: .done)
        }
        #expect(try vault.read(project: "alpha", status: .done, file: file) == "keep me")
    }

    @Test func duplicateTitlesGetDistinctFiles() throws {
        let a = try vault.create(project: "alpha", title: "Same")
        let b = try vault.create(project: "alpha", title: "Same")
        #expect(a != b)
    }

    @Test func slugs() {
        #expect(Vault.slug("Café — déjà vu!") == "cafe-deja-vu")
        #expect(Vault.slug("***") == "card")
    }
}
