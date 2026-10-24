import Foundation

public enum WorktreeError: LocalizedError, Equatable {
    case notARepository(String)
    case noCommits(String)

    public var errorDescription: String? {
        switch self {
        case .notARepository(let path): "\(path) isn’t a git repository, so workers can’t get their own checkout."
        case .noCommits(let path): "\(path) has no commits yet. Make a first commit so workers can branch from it."
        }
    }
}

/// One isolated checkout per worker, so parallel agents never edit the same
/// files. Worktrees share the repository's history, so their branches can be
/// pushed and turned into pull requests as usual.
public enum GitWorktree {
    public struct Checkout: Sendable, Equatable {
        public var path: URL
        public var branch: String
    }

    /// Creates (or reuses) `<root>/<slug>` on branch `codefactory/<slug>`,
    /// branched from the repository's current HEAD.
    public static func checkout(
        repository: URL,
        slug: String,
        root: URL,
        git: URL = URL(filePath: "/usr/bin/git")
    ) async throws -> Checkout {
        let name = try CardBoard.segment(slug)
        let branch = "codefactory/\(name)"
        let path = root.appending(path: name, directoryHint: .isDirectory)

        let inside = try? await ProcessRunner.run(git, ["-C", repository.path, "rev-parse", "--is-inside-work-tree"], check: false)
        guard inside?.status == 0 else { throw WorktreeError.notARepository(repository.path) }
        let head = try? await ProcessRunner.run(git, ["-C", repository.path, "rev-parse", "--verify", "HEAD"], check: false)
        guard head?.status == 0 else { throw WorktreeError.noCommits(repository.path) }

        // Resume: the worktree is already there.
        if FileManager.default.fileExists(atPath: path.appending(path: ".git").path) {
            return Checkout(path: Project.canonical(path), branch: branch)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let branchExists = (try? await ProcessRunner.run(
            git, ["-C", repository.path, "rev-parse", "--verify", "--quiet", "refs/heads/\(branch)"], check: false
        ))?.status == 0
        let args = branchExists
            ? ["-C", repository.path, "worktree", "add", path.path, branch]
            : ["-C", repository.path, "worktree", "add", "-b", branch, path.path, "HEAD"]
        try await ProcessRunner.run(git, args)
        return Checkout(path: Project.canonical(path), branch: branch)
    }
}
