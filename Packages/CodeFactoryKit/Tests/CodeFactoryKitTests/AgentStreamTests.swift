import Foundation
import Testing
@testable import CodeFactoryKit

@Suite struct AgentStreamTests {
    let log = """
    {"type":"system","subtype":"init"}
    {"type":"assistant","message":{"content":[{"type":"text","text":"Planning now."},{"type":"tool_use","name":"Read","input":{"file_path":"/Users/me/reviewdesk/README.md"}}]}}
    {"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"Claude requested permissions to read from /Users/me/reviewdesk/README.md, but you haven't granted it yet."}]}}
    {"type":"assistant","message":{"content":[{"type":"text","text":"<!--TTS: hidden -->Wrote 15 cards."}]}}
    {"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.42,"result":"<!--TTS: x -->Wrote 15 cards.","permission_denials":[{"tool_name":"Read","tool_use_id":"t1","tool_input":{"file_path":"/Users/me/reviewdesk/README.md"}},{"tool_name":"Bash","tool_use_id":"t2","tool_input":{"command":"npm install"}}]}
    """

    @Test func summaryListsDenials() throws {
        let s = try #require(AgentStream.summary(of: log))
        #expect(s.result == "Wrote 15 cards.")
        #expect(s.denials.count == 2)
        #expect(s.denials[0].path == "/Users/me/reviewdesk/README.md")
        #expect(s.denials[1].command == "npm install")
        #expect(s.costUSD == 0.42)
    }

    @Test func suggestsTheFolderOutsideTheRepo() throws {
        let s = try #require(AgentStream.summary(of: log))
        let dirs = s.directoriesToAllow(outside: URL(filePath: "/Users/me/app"))
        #expect(dirs.map(\.path) == ["/Users/me/reviewdesk"])
        #expect(s.directoriesToAllow(outside: URL(filePath: "/Users/me/reviewdesk")).isEmpty)
    }

    @Test func rendersReadably() {
        let text = AgentStream.render(log)
        #expect(text.contains("● Planning now."))
        #expect(text.contains("⏺ Read("))
        #expect(text.contains("✗ Claude requested permissions"))
        #expect(text.contains("⚠ Needed permission for:"))
        #expect(text.contains("Run `npm install`"))
        #expect(!text.contains("TTS"))
    }

    @Test func plainTextLogsPassThrough() {
        #expect(AgentStream.render("hello\nworld") == "hello\nworld")
        #expect(AgentStream.summary(of: "hello") == nil)
    }
}

@Suite struct ProjectPathTests {
    @Test func canonicalUsesOnDiskSpelling() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "cf-case-\(UUID().uuidString)")
        let real = base.appending(path: "MixedCase", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let wrong = base.appending(path: "mixedcase", directoryHint: .isDirectory)
        #expect(Project.canonical(wrong).lastPathComponent == "MixedCase")
        #expect(Project(repository: wrong).repository.lastPathComponent == "MixedCase")
    }

    @Test func cardsElsewhereAreAllowedAutomatically() {
        let p = Project(repository: URL(filePath: "/tmp/nope-repo"), cardsOverride: URL(filePath: "/tmp/nope-vault/Work/app"),
                        allowedDirectories: [URL(filePath: "/tmp/nope-ref")])
        #expect(p.extraDirectories.map(\.path) == ["/tmp/nope-vault/Work/app", "/tmp/nope-ref"])
        #expect(Project(repository: URL(filePath: "/tmp/nope-repo")).extraDirectories.isEmpty)
    }

    @Test func oldProjectFilesStillDecode() throws {
        let json = #"[{"id":"1","name":"a","repository":"file:///tmp/a/"}]"#
        let projects = try JSONDecoder().decode([Project].self, from: Data(json.utf8))
        #expect(projects.first?.allowedDirectories == [])
    }
}
