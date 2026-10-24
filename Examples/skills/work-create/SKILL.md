---
name: work-create
description: Turn a one-line idea into a work card in the Code Factory vault. Use when invoked as /work-create followed by an idea.
---

# Create a work card

You were given a short idea after the command. Turn it into one well-formed
card and stop.

1. Find the vault. Code Factory sets `CODE_FACTORY_VAULT`,
   `CODE_FACTORY_WORK_FOLDER` (usually `Work`) and `CODE_FACTORY_PROJECT` in
   your environment; if they are missing, ask the user. Cards go in
   `$CODE_FACTORY_VAULT/$CODE_FACTORY_WORK_FOLDER/$CODE_FACTORY_PROJECT/todo/`.
2. Look at the repository just enough to make the card concrete — relevant
   files, existing tests, conventions. Do not change any code.
3. Write `<slug-of-title>.md` with this shape:

   ```markdown
   ---
   title: Short imperative title
   status: todo
   kind: feature | bug | chore | refactor | spike | docs
   created: YYYY-MM-DD
   updated: YYYY-MM-DD
   ---

   ## Goal

   One paragraph: what and why.

   ## Acceptance criteria

   - [ ] Observable, testable outcomes
   ```

4. Never overwrite an existing file; add `-2`, `-3`… to the name instead.
