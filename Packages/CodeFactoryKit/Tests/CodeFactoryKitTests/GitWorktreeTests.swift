import Foundation
import Testing
@testable import CodeFactoryKit

@Suite struct GitWorktreeTests {
    let git = URL(filePath: "/usr/bin/git")

    func makeRepo(commit: Bool) async throws -> URL {
        let repo = FileManager.default.temporaryDirectory.appending(path: "cf-wt-\(UUID().uuidString)/app")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try await ProcessRunner.run(git, ["init", "--quiet", "--initial-branch=main"], currentDirectory: repo)
        if commit {
            try "hello".write(to: repo.appending(path: "README.md"), atomically: true, encoding: .utf8)
            try await ProcessRunner.run(git, ["add", "."], currentDirectory: repo)
            try await ProcessRunner.run(git, ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "--quiet", "-m", "init"], currentDirectory: repo)
        }
        return repo
    }

    @Test func createsAnIsolatedCheckoutAndReusesIt() async throws {
        let repo = try await makeRepo(commit: true)
        let root = repo.deletingLastPathComponent().appending(path: "worktrees")
        let a = try await GitWorktree.checkout(repository: repo, slug: "relay", root: root)
        #expect(a.branch == "codefactory/relay")
        #expect(FileManager.default.fileExists(atPath: a.path.appending(path: "README.md").path))
        let branch = try await ProcessRunner.run(git, ["-C", a.path.path, "branch", "--show-current"])
        #expect(branch.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "codefactory/relay")
        let again = try await GitWorktree.checkout(repository: repo, slug: "relay", root: root)
        #expect(again == a)
    }

    @Test func refusesReposWithoutCommits() async throws {
        let repo = try await makeRepo(commit: false)
        await #expect(throws: WorktreeError.self) {
            try await GitWorktree.checkout(repository: repo, slug: "x", root: repo.deletingLastPathComponent())
        }
    }
}
