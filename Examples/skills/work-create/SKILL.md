---
name: work-create
description: Turn a one-line idea into a Ultra Code Factory work card. Use when invoked as /work-create followed by an idea.
---

# Create a work card

You were given a short idea after the command. Turn it into one well-formed
card and stop.

1. Find the board. Ultra Code Factory sets `CODE_FACTORY_CARDS` (the project's cards
   folder, usually `<repo>/.codefactory`) and `CODE_FACTORY_PROJECT` in your
   environment. Without them, use `./.codefactory`. New cards go in
   `$CODE_FACTORY_CARDS/todo/`.
2. Read `PROJECT.md` if it exists, then look at the repository just enough to
   make the card concrete: relevant files, existing tests, conventions. Do
   not change any code.
3. Write `<slug-of-title>.md` with this shape:

   ```markdown
   ---
   title: Short imperative title
   status: todo
   kind: feature | bug | chore | refactor | spike | docs
   priority: high | medium | low
   created: YYYY-MM-DD
   updated: YYYY-MM-DD
   ---

   ## Goal

   One paragraph: what and why.

   ## Acceptance criteria

   - [ ] Observable, testable outcomes
   ```

4. Never overwrite an existing file; add `-2`, `-3`… to the name instead.
