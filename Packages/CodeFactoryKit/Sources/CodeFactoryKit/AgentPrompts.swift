import Foundation

/// Built-in first messages for each agent action, so a fresh install works
/// without any user skills. Each can be overridden with a slash command in
/// Settings.
public enum AgentPrompts {
    static func board(_ cards: URL) -> String {
        """
        This project's work cards live in \(cards.path), one markdown file per card, in one folder per status: \
        proposed, todo, picked-up, waiting, done, wont-do. A card's folder is its status; when you move a card, \
        also update the `status:` and `updated:` (YYYY-MM-DD) lines in its frontmatter. Never overwrite or delete a card. \
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
        title, status: todo, kind (feature | bug | chore | refactor | spike | docs), priority (high | medium | low), created and updated, \
        then "## Goal" (what and why, one paragraph) and "## Acceptance criteria" (a checklist of observable outcomes).
        """
    }

    /// Pick up a card (or the next one) and take it all the way to a pull request.
    public static func work(card: String?, cardsFolder: URL) -> String {
        let which = card.map { "Work on the card \($0)." }
            ?? "Pick the highest-priority, oldest card in the todo folder."
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
}
