# Contributing

Thanks for helping build the factory.

1. `brew install xcodegen tmux`
2. `make test` runs the CodeFactoryKit unit tests (Swift Testing).
3. `make run` builds and launches the app.

Guidelines:

- Keep filesystem and process logic in `Packages/CodeFactoryKit`, where it
  can be unit tested, and keep SwiftUI in `App/`.
- Anything that touches paths, processes or tmux must keep the guarantees in
  [SECURITY.md](SECURITY.md). Add a test when you change them.
- Don't commit generated files (`CodeFactory.xcodeproj`, `build/`), signing
  identities, or any personal paths.
- To test agent flows without spending tokens, point **Settings → Agents →
  claude** at a small script that prints a numbered `❯ 1. …` option list and
  echoes stdin.

By contributing, you agree that your contributions are licensed under the MIT
License.

To try agent flows end to end without touching your real projects, run the
Debug app with `UCF_SUPPORT_DIR=/some/scratch/folder` (projects, jobs, logs and
worktrees go there) and `-claudePath /path/to/fake-claude` as a launch argument.
