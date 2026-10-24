import Foundation

public struct ProcessResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
}

public enum ProcessRunnerError: LocalizedError {
    case failed(command: String, status: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .failed(let command, let status, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(command) exited with status \(status)\(detail.isEmpty ? "" : ": \(detail)")"
        }
    }
}

/// Runs a short-lived command and collects its output. Arguments are passed
/// straight to `execve` — never through a shell — so nothing in them is ever
/// interpreted as shell syntax.
public enum ProcessRunner {
    /// GUI apps on macOS launch with a bare PATH; agents and their tools
    /// expect the usual developer install locations to be reachable.
    public static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extras = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.claude/local"]
        var parts = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        for dir in extras.reversed() where !parts.contains(dir) {
            parts.insert(dir, at: 0)
        }
        env["PATH"] = parts.joined(separator: ":")
        return env
    }

    @discardableResult
    public static func run(
        _ executable: URL,
        _ arguments: [String],
        currentDirectory: URL? = nil,
        check: Bool = true
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        let result: ProcessResult = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                // Drain both pipes concurrently so neither can fill and stall the child.
                let group = DispatchGroup()
                nonisolated(unsafe) var errData = Data()
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                continuation.resume(returning: ProcessResult(
                    status: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self)
                ))
            }
        }
        if check, result.status != 0 {
            throw ProcessRunnerError.failed(
                command: ([executable.lastPathComponent] + arguments.prefix(1)).joined(separator: " "),
                status: result.status,
                stderr: result.stderr
            )
        }
        return result
    }
}

/// Finds command-line tools the way a login shell would, without spawning one.
public enum BinaryLocator {
    public static func locate(_ name: String, override: String? = nil) -> URL? {
        let fm = FileManager.default
        if let override, !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: expanded) ? URL(filePath: expanded) : nil
        }
        let dirs = (ProcessRunner.environment["PATH"] ?? "").split(separator: ":")
        for dir in dirs {
            let candidate = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: candidate) { return URL(filePath: candidate) }
        }
        return nil
    }
}
