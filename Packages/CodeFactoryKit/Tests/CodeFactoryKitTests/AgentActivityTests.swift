import Foundation
import Testing
@testable import CodeFactoryKit

@Suite struct AgentActivityTests {
    let transcript = """
    {"type":"assistant","timestamp":"2026-10-24T21:14:30.100Z","message":{"content":[{"type":"text","text":"<!--TTS: x -->Reading the card first."},{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls -R .codefactory","description":"List cards"}}]}}
    {"type":"user","timestamp":"2026-10-24T21:14:31.600Z","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"todo/\\nwaiting/"}]}}
    {"type":"assistant","timestamp":"2026-10-24T21:14:32Z","message":{"content":[{"type":"tool_use","id":"t2","name":"Edit","input":{"file_path":"/tmp/a.swift","old_string":"a\\nb","new_string":"a\\nb\\nc"}}]}}
    {"type":"user","timestamp":"2026-10-24T21:14:33Z","message":{"content":[{"type":"tool_result","tool_use_id":"t2","is_error":true,"content":[{"type":"text","text":"String not found"}]}]}}
    {"type":"assistant","timestamp":"2026-10-24T21:14:34Z","message":{"content":[{"type":"tool_use","id":"t3","name":"Bash","input":{"command":"swift test"}}]}}
    """

    @Test func buildsATimeline() {
        let steps = ActivityParser.parse(transcript)
        #expect(steps.count == 4)
        #expect(steps[0].kind == .said && steps[0].title == "Reading the card first.")
        #expect(steps[1].tool == "Bash" && steps[1].title == "ls -R .codefactory" && steps[1].subtitle == "List cards")
        #expect(steps[1].output == "todo/\nwaiting/")
        #expect(abs((steps[1].duration ?? 0) - 1.5) < 0.01)
        #expect(steps[2].subtitle == "+3 −2")
        #expect(steps[2].isError && steps[2].output == "String not found")
        #expect(steps[3].isRunning)
    }

    @Test func incrementalIngestMatchesWholeParse() {
        var parser = ActivityParser()
        let lines = transcript.split(separator: "\n")
        parser.ingest(lines.prefix(2))
        parser.ingest(lines.dropFirst(2))
        #expect(parser.steps.map(\.title) == ActivityParser.parse(transcript).map(\.title))
    }

    @Test func transcriptFolderMatchesClaudeCodesNaming() {
        let folder = ClaudeTranscript.folder(for: URL(filePath: "/Users/me/Library/Application Support/Ultra Code Factory/worktrees/A-1/card"),
                                             home: URL(filePath: "/Users/me"))
        #expect(folder.lastPathComponent == "-Users-me-Library-Application-Support-Ultra-Code-Factory-worktrees-A-1-card")
    }
}
