import CodeFactoryKit
import Foundation

/// Builds a small, self-contained sample vault so a fresh install has
/// something to look at before you point it at real work.
enum DemoFactory {
    static var root: URL { Preferences.supportDirectory.appending(path: "Demo", directoryHint: .isDirectory) }

    static func install() throws {
        let vaultRoot = root.appending(path: "vault", directoryHint: .isDirectory)
        let reposRoot = root.appending(path: "repos", directoryHint: .isDirectory)
        let vault = Vault(vaultRoot: vaultRoot, workFolder: "Work")
        let project = "demo-factory"
        try vault.createProject(project)

        let repo = reposRoot.appending(path: project, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        # demo-factory

        A scratch repository for trying Code Factory. Agents you launch from
        the demo board run here, so nothing they do touches your real code.

        """.write(to: repo.appending(path: "README.md"), atomically: true, encoding: .utf8)

        let samples: [(String, String, CardStatus, String)] = [
            ("Add a dark-mode toggle to the settings page", "feature", .proposed,
             "## Goal\n\nLet people pick light, dark or system appearance.\n\n## Acceptance criteria\n\n- [ ] Toggle persists across launches\n- [ ] Defaults to *system*"),
            ("Crash when the config file is empty", "bug", .todo,
             "## Repro\n\n1. Create an empty `config.json`\n2. Launch the app\n\n## Expected\n\nA friendly error instead of a crash.\n\n- [ ] Add a failing test\n- [ ] Fix the parser"),
            ("Write the getting-started guide", "docs", .todo,
             "## Outline\n\n- Install\n- First project\n- Your first agent run\n\n> Keep it under five minutes of reading."),
            ("Extract the HTTP client into its own module", "refactor", .pickedUp,
             "## Plan\n\n- [x] Inventory call sites\n- [ ] Move the client\n- [ ] Update imports\n\n```swift\nlet client = HTTPClient(baseURL: url)\n```"),
            ("Pick a charting library", "spike", .waiting,
             "## Question\n\nWe need a decision from the team before going further.\n\n- Option A: native Swift Charts\n- Option B: a web view"),
            ("Set up continuous integration", "chore", .done,
             "## Done\n\n- [x] Build on every push\n- [x] Run the test suite"),
            ("Rewrite everything in COBOL", "spike", .wontDo,
             "Tempting, but no."),
        ]
        for (title, kind, status, body) in samples {
            let file = "\(Vault.slug(title)).md"
            if (try? vault.read(project: project, status: status, file: file)) == nil {
                try vault.create(project: project, title: title, kind: kind, status: status, body: body)
            }
        }

        let defaults = UserDefaults.standard
        defaults.set(vaultRoot.path, forKey: Pref.vaultPath)
        defaults.set("Work", forKey: Pref.workFolder)
        defaults.set(reposRoot.path, forKey: Pref.reposPath)
        defaults.set(project, forKey: Pref.selectedProject)
    }
}
