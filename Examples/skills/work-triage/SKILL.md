---
name: work-triage
description: Walk the Code Factory backlog with the user, one card at a time. Use when invoked as /work-triage.
---

# Triage the backlog

Go through `proposed/` and `waiting/` cards for this project one at a time.
For each, summarise it in two sentences and ask the user — with the
AskUserQuestion tool, so Code Factory can show native buttons — whether to
move it to `todo`, keep it, or move it to `wont-do`. Apply the answer by
moving the file and updating `status:` / `updated:` in its frontmatter.
