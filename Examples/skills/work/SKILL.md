---
name: work
description: Pick up the next Ultra Code Factory card, build it, and open a pull request. Use when invoked as /work, optionally followed by a card filename.
---

# Work the next card

The board lives in `$CODE_FACTORY_CARDS` (falls back to `./.codefactory`),
with one folder per status.

1. If a filename was given, use that card; otherwise take the highest-priority,
   oldest card in `todo/`. Read `PROJECT.md` first if it exists.
2. Move the card to `picked-up/` and update `status:` and `updated:` in its
   frontmatter before starting.
3. Create a branch named after the card, implement it, and add or update
   tests. Tick acceptance criteria in the card as you meet them.
4. Commit, push, and open a pull request with `gh pr create`, linking the
   card's title and acceptance criteria in the description.
5. Add the PR URL to the bottom of the card, then move it to `waiting/`: it
   is now waiting on the human's review. Move it to `done/` only after the PR
   is merged.
6. If you need a decision before you can finish, write the question at the
   bottom of the card, move it to `waiting/`, and ask.

Ask before anything destructive or irreversible.
