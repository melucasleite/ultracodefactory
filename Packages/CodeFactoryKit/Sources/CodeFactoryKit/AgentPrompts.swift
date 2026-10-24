import Foundation

/// Built-in first messages for each agent action, so a fresh install works
/// without any user skills. Each can be overridden with a slash command in
/// Settings.
public enum AgentPrompts {
    static func board(_ cards: URL) -> String {
        """
        This project's work cards live in \(cards.path), one markdown file per card, in one folder per status: \
        proposed, todo, picked-up, waiting, done, wont-do. A card's folder is its status; when you move a card, \
        also update the `status:` and `updated:` (YYYY-MM-DD) lines in its frontmatter. `order:` is the project's build \
        sequence (1 = first); keep it when moving cards. Never overwrite or delete a card. Cards move, so before you edit or append to a card, \
        find where it is now (`ls <cards folder>/*/<name>.md`) and edit that file; never create a card file in a folder it isn't in. \
        Read PROJECT.md first if it exists.
        """
    }

    /// Turn a one-line idea into one well-formed card in To-Do.
    public static func create(idea: String, cardsFolder: URL) -> String {
        """
        \(board(cardsFolder))

        Turn this idea into exactly one work card and stop: "\(idea)"

        Look at the repository just enough to make the card concrete (relevant files, tests, conventions), but do not change any code. \
        Write it to \(cardsFolder.appending(path: CardStatus.todo.rawValue).path)/<kebab-case-title>.md with frontmatter \
        title, status: todo, kind (feature | bug | chore | refactor | spike | docs), priority (high | medium | low), \
        order (one more than the highest order on the board), created and updated, \
        then "## Goal" (what and why, one paragraph) and "## Acceptance criteria" (a checklist of observable outcomes).
        """
    }

    /// Pick up a card (or the next one) and take it all the way to a pull request.
    public static func work(card: String?, cardsFolder: URL) -> String {
        let which = card.map { "Work on the card \($0)." }
            ?? "Pick the card in the todo folder with the lowest `order:` (if none have one, the highest-priority, oldest card)."
        return """
        \(board(cardsFolder))

        \(which) Move it to picked-up before you start. Create a branch named after the card, implement it with tests, \
        and tick its acceptance criteria as you meet them. When it's done, commit, push and open a pull request (use `gh pr create` \
        if the GitHub CLI is available), add the PR URL to the bottom of the card, and move the card to waiting, where it waits for review. \
        If you need a decision before you can finish, write the question at the bottom of the card, move it to waiting, and ask me. \
        Ask before anything destructive or irreversible.
        """
    }

    /// Walk the backlog with the human, one card at a time.
    public static func triage(cardsFolder: URL) -> String {
        """
        \(board(cardsFolder))

        Let's triage the backlog together. Go through the cards in proposed and waiting one at a time. For each, summarise it \
        in two sentences, then ask me what to do using the AskUserQuestion tool with options such as: move to To-Do, keep it, \
        split it, or won't do. Apply my answer by moving or editing the card, then go to the next one. Finish with a short summary.
        """
    }

    /// One of several parallel workers, each in its own worktree on its own card.
    public static func worker(card: String, branch: String, cardsFolder: URL) -> String {
        """
        \(board(cardsFolder))

        You are one of several Ultra Code Factory workers running in parallel. You are in your own git worktree on branch `\(branch)`, so your changes can't collide with other workers. Work only on the card \(card).md: do not pick up, move or edit any other card.

        First move \(card).md to picked-up. Implement it with tests on this branch and tick its acceptance criteria as you go. When it's done, commit, push the branch and open a pull request (use `gh pr create` if the GitHub CLI is available). Add the PR URL to the bottom of the card and move it to waiting, where it waits for review. If you need a decision before you can finish, write the question at the bottom of the card, leave it in picked-up and ask me. Ask before anything destructive or irreversible.
        """
    }

    /// Fill in `depends_on:` across an existing board.
    public static func mapDependencies(cardsFolder: URL) -> String {
        """
        \(board(cardsFolder))

        Map the dependencies between the cards so several agents can build them in parallel. Read every card in every status folder, then for each card in proposed, todo and picked-up set a single `depends_on:` frontmatter line listing the cards that must be finished (merged) before it can start, by file name without .md, for example `depends_on: [set-up-monorepo-skeleton]`, or `depends_on: []` if it can start right away.

        Rules: list only direct prerequisites, not everything upstream. Be strict: a dependency means the work truly can't start without the other card's code, not just that it comes later. Never create a cycle. Change only the `depends_on:` line of each card. Don't edit anything else, and don't create, move or delete cards. Finish with a short summary of how many cards are ready now and the longest chain.
        """
    }

    /// Resolve a pull request's merge conflicts without changing its scope.
    public static func fixConflicts(card: String, pullRequest: Int, branch: String, base: String, cardsFolder: URL) -> String {
        """
        \(board(cardsFolder))

        Pull request #\(pullRequest) for the card \(card).md has merge conflicts with `\(base)`. You are in the PR's worktree on branch `\(branch)`.

        Fetch the latest `\(base)` and merge it into this branch (`git fetch origin && git merge origin/\(base)`), resolve every conflict so both sides' intent is preserved, then build and run the tests. Don't change what the card is about or rewrite unrelated code. Commit the resolution, push the branch, and confirm with `gh pr view \(pullRequest) --json mergeable` that GitHub no longer reports conflicts. Leave the card in waiting. If a conflict is genuinely ambiguous, write the question at the bottom of the card and ask me rather than guessing.
        """
    }
}
