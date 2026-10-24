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

    var createCommand: String { string(Pref.createCommand) }
    var workCommand: String { string(Pref.workCommand) }
    var triageCommand: String { string(Pref.triageCommand) }
    var notifications: Bool { defaults.bool(forKey: Pref.notifications) }
    var permissionMode: PermissionMode {
        PermissionMode(rawValue: string(Pref.permissionMode)) ?? .acceptEdits
    }

    var claude: URL? { BinaryLocator.locate("claude", override: string(Pref.claudePath)) }
    var tmux: URL? { BinaryLocator.locate("tmux", override: string(Pref.tmuxPath)) }

    static var supportDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Ultra Code Factory", directoryHint: .isDirectory)
    }
}
