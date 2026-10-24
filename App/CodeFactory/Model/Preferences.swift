import CodeFactoryKit
import Foundation

/// UserDefaults keys and defaults. Views bind with `@AppStorage(Pref.x)`;
/// the model reads through `Preferences` so both agree on defaults.
enum Pref {
    static let vaultPath = "vaultPath"
    static let workFolder = "workFolder"
    static let reposPath = "reposPath"
    static let claudePath = "claudePath"
    static let tmuxPath = "tmuxPath"
    static let createCommand = "createCommand"
    static let workCommand = "workCommand"
    static let triageCommand = "triageCommand"
    static let permissionMode = "permissionMode"
    static let notifications = "notifications"
    static let selectedProject = "selectedProject"
}

struct Preferences {
    var defaults: UserDefaults = .standard

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Pref.workFolder: "Work",
            Pref.createCommand: "/work-create",
            Pref.workCommand: "/work",
            Pref.triageCommand: "/work-triage",
            Pref.permissionMode: PermissionMode.acceptEdits.rawValue,
            Pref.notifications: true,
        ])
    }

    private func string(_ key: String) -> String {
        (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func url(_ key: String) -> URL? {
        let path = string(key)
        guard !path.isEmpty else { return nil }
        return URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    }

    var vaultRoot: URL? { url(Pref.vaultPath) }
    var workFolder: String { string(Pref.workFolder).isEmpty ? "Work" : string(Pref.workFolder) }
    /// Defaults to the vault's parent: one repo per project, named like the project.
    var reposRoot: URL? { url(Pref.reposPath) ?? vaultRoot?.deletingLastPathComponent() }
    var createCommand: String { string(Pref.createCommand) }
    var workCommand: String { string(Pref.workCommand) }
    var triageCommand: String { string(Pref.triageCommand) }
    var notifications: Bool { defaults.bool(forKey: Pref.notifications) }
    var permissionMode: PermissionMode {
        PermissionMode(rawValue: string(Pref.permissionMode)) ?? .acceptEdits
    }

    var claude: URL? { BinaryLocator.locate("claude", override: string(Pref.claudePath)) }
    var tmux: URL? { BinaryLocator.locate("tmux", override: string(Pref.tmuxPath)) }

    var vault: Vault? {
        vaultRoot.map { Vault(vaultRoot: $0, workFolder: workFolder) }
    }

    static var supportDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Code Factory", directoryHint: .isDirectory)
    }
}
