import CodeFactoryKit
import Foundation

/// UserDefaults keys and defaults. Views bind with `@AppStorage(Pref.x)`;
/// the model reads through `Preferences` so both agree on defaults.
enum Pref {
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
            Pref.permissionMode: PermissionMode.acceptEdits.rawValue,
            Pref.notifications: true,
        ])
    }

    private func string(_ key: String) -> String {
        (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var createCommand: String { string(Pref.createCommand) }
    var workCommand: String { string(Pref.workCommand) }
    var triageCommand: String { string(Pref.triageCommand) }
    var notifications: Bool { defaults.bool(forKey: Pref.notifications) }
    var permissionMode: PermissionMode {
        PermissionMode(rawValue: string(Pref.permissionMode)) ?? .acceptEdits
    }

    var claude: URL? { BinaryLocator.locate("claude", override: string(Pref.claudePath)) }
    var tmux: URL? { BinaryLocator.locate("tmux", override: string(Pref.tmuxPath)) }
    var gh: URL? { BinaryLocator.locate("gh") }

    /// Where projects, jobs, logs and worktrees live. `UCF_SUPPORT_DIR`
    /// points a development run at a scratch folder instead.
    static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["UCF_SUPPORT_DIR"], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "Ultra Code Factory", directoryHint: .isDirectory)
    }
}
