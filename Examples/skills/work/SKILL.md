---
name: work
description: Pick up the next card from the Code Factory vault and implement it. Use when invoked as /work, optionally followed by a card filename.
---

# Work the next card

1. Locate `<vault>/Work/<project>/` for this repository (see `work-create`).
2. If a filename was given, use that card; otherwise take the oldest card in
   `todo/`.
3. Move it to `picked-up/` (update `status:` and `updated:` in the
   frontmatter) before starting.
4. Implement it in the repository. Tick acceptance criteria as you meet them.
5. When finished, move the card to `done/`. If you need a decision from the
   human, explain what you need at the bottom of the card, move it to
   `waiting/`, and ask.

Ask before anything destructive or irreversible.
