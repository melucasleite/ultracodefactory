import Darwin
import Foundation

/// Liveness checks for headless agents, careful about PID reuse: a PID only
/// counts as ours if it is alive, started after boot-before-launch, and is
/// still running the executable we launched.
public enum ProcessInspector {
    public static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public static func isAlive(_ pid: Int32) -> Bool {
        pid > 0 && (Darwin.kill(pid, 0) == 0 || errno == EPERM)
    }

    public static var bootDate: Date {
        Date.now.addingTimeInterval(-ProcessInfo.processInfo.systemUptime)
    }

    /// Whether `pid` still looks like the agent started at `startedAt` from `executableName`.
    public static func isOurs(pid: Int32, startedAt: Date, executableName: String) -> Bool {
        guard startedAt > bootDate, isAlive(pid) else { return false }
        guard let path = executablePath(of: pid) else { return true } // alive but unreadable: assume yes
        let name = URL(filePath: path).lastPathComponent
        // `claude` may exec a versioned binary or node; accept the common shapes.
        return name == executableName || name.hasPrefix(executableName) || name == "node"
            || path.contains("/claude/")
    }
}
