<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Code Factory icon">
</p>

<h1 align="center">Code Factory</h1>

<p align="center">
  A native macOS kanban board for markdown work cards, staffed by
  <a href="https://docs.claude.com/en/docs/claude-code">Claude Code</a> agents.
</p>

---

Code Factory turns a folder of markdown files into a production line. Each
card is a plain `.md` file; each column is a folder. Drag a card and the file
moves. Ask for work and an agent writes the card. Hit **Run Work** and an
agent picks it up in the project's repository, while you watch its terminal,
answer its questions with real buttons, and get a notification when it needs
you.

Your cards stay plain text, so they work just as well in Obsidian, your
editor, `git`, or `grep`.

## Features

- **Live kanban board**: six stations (Proposed, To-Do, Picked Up, Waiting,
  Done, Won't Do), drag and drop, search and kind filters. The board updates
  instantly when files change on disk, whether you, an agent, or Obsidian
  changed them (FSEvents).
- **Card editor**: rendered markdown with clickable task checkboxes that
  write straight back to the file, plus a raw editor (⌘S).
- **Create Work**: describe an idea; a headless `claude -p` agent turns it
  into a card while a "fabricating" placeholder holds its spot on the board.
- **Run Work / Triage / Open Session**: interactive Claude Code sessions
  inside detached `tmux` sessions, one per job.
- **Console windows**: a colour terminal mirror of each agent, keyboard
  passthrough, and Claude's multiple-choice prompts drawn as native buttons
  (⌘1–⌘9).
- **Factory floor**: an inspector listing every agent with live status,
  elapsed time, stop, and attach-from-your-terminal commands.
- **Menu bar extra and notifications** for agents that finish or need input.
- **Demo factory**: a sample vault and scratch repo, so you can try it
  without pointing it at real work.

## Requirements

- macOS 15 or later
- [Claude Code](https://docs.claude.com/en/docs/claude-code) (`claude` on your PATH)
- [tmux](https://github.com/tmux/tmux) 3.2 or later (`brew install tmux`), for interactive agents
- To build: Xcode 16 or later, plus [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build and run

```bash
make run
```

That generates the Xcode project, builds a Debug app (signed ad hoc, so no
Apple developer account is needed), and launches it. `make test` runs the
unit tests and `make project` just generates `CodeFactory.xcodeproj` so you
can open it in Xcode.

## Vault layout

```
vault/
└─ Work/                       ← "work folder" (configurable)
   └─ my-project/              ← one folder per project
      ├─ proposed/
      ├─ todo/
      ├─ picked-up/
      ├─ waiting/
      ├─ done/
      └─ wont-do/              ← one card per .md file
repos/
└─ my-project/                 ← agents for "my-project" run here
```

A card is markdown with optional flat frontmatter:

```markdown
---
title: Crash when the config file is empty
status: todo
kind: bug # feature | bug | chore | refactor | spike | docs | anything
id: 42 # optional, shown as #42
priority: high # optional
updated: 2026-10-23
---

## Acceptance criteria

- [ ] Add a failing test
- [ ] Fix the parser
```

The folder a card is in is its real status. When you move a card, Code
Factory also rewrites the `status:` and `updated:` lines and leaves every
other byte alone.

## Agents

Each toolbar action sends the agent a configurable slash command as its first
message (**Settings → Agents**):

| Action       | Default        | Mode                   |
| ------------ | -------------- | ---------------------- |
| Create Work  | `/work-create` | headless (`claude -p`) |
| Run Work     | `/work`        | interactive (tmux)     |
| Triage       | `/work-triage` | interactive (tmux)     |
| Open Session | none           | interactive (tmux)     |

Example skills that implement these commands are in
[`Examples/skills`](Examples/skills). Copy them into `~/.claude/skills/` or a
project's `.claude/skills/` and adjust them to taste. Agents also receive
`CODE_FACTORY_VAULT`, `CODE_FACTORY_WORK_FOLDER` and `CODE_FACTORY_PROJECT`
in their environment.

To attach to any interactive agent from your own terminal, copy the
`tmux attach -t codefactory-…` command from its console.

## Safety

Code Factory launches AI agents that can change files in your repositories.
Read [SECURITY.md](SECURITY.md) before you use it on code you care about. In
short:

- Agents start in **Accept file edits** permission mode. **Bypass all
  permissions** has to be switched on deliberately, and the app warns you
  when you do.
- The app is not sandboxed, because launching `tmux` and `claude` is the
  whole point. It sends nothing over the network; any network traffic comes
  from the agents you start.
- Commands run without a shell, and every file name from the outside world is
  validated, so nothing can escape the vault.
- Deleted cards go to the Trash, and a move never overwrites an existing
  card.

## Project structure

```
App/CodeFactory/            SwiftUI app: views, models, theme, assets
Packages/CodeFactoryKit/    Pure-Swift core with unit tests
  Vault.swift               cards on disk, path validation
  Frontmatter.swift         surgical frontmatter edits
  AgentLauncher.swift       headless and tmux agents, permission modes
  JobStore.swift            persistent job ledger and liveness checks
  QuestionParser.swift      Claude's option prompts → native buttons
  ANSI.swift                terminal colours → styled text
Examples/skills/            sample /work-create, /work, /work-triage skills
Scripts/make-icon.swift     the app icon, drawn in code
```

## License

[MIT](LICENSE)

Code Factory is an independent project. It is not affiliated with or endorsed
by Anthropic. "Claude" and "Claude Code" are trademarks of their owner.
