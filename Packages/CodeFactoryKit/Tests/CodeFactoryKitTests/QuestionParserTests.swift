import Testing
@testable import CodeFactoryKit

@Suite struct QuestionParserTests {
    @Test func parsesSingleSelect() throws {
        let pane = """
        ● Working on it.

        ╭──────────────────────────────────╮
        │ Which database should we use?    │
        │ ❯ 1. Postgres                    │
        │      Battle-tested relational    │
        │   2. SQLite                      │
        │   3. Something else              │
        ╰──────────────────────────────────╯
        """
        let q = try #require(QuestionParser.parse(pane))
        #expect(q.text == "Which database should we use?")
        #expect(q.options.map(\.label) == ["Postgres", "SQLite", "Something else"])
        #expect(q.pointer == 0)
        #expect(!q.multiSelect)
        #expect(q.keys(toChoose: 2) == [.down, .down, .enter])
        #expect(q.keys(toChoose: 0) == [.enter])
    }

    @Test func parsesMultiSelect() throws {
        let pane = """
        Pick the checks to run
          ◉ 1. Lint
        ❯ ○ 2. Tests
          ○ 3. Build
        """
        let q = try #require(QuestionParser.parse(pane))
        #expect(q.multiSelect)
        #expect(q.pointer == 1)
        #expect(q.options[0].checked)
        #expect(!q.options[1].checked)
        #expect(q.keys(toChoose: 0) == [.up, .space])
    }

    @Test func ignoresOrdinaryNumberedProse() {
        let pane = """
        Here's the plan:
        1. Read the code
        2. Write the fix
        3. Run the tests
        """
        #expect(QuestionParser.parse(pane) == nil)
    }

    @Test func rejectsTwoPointers() {
        #expect(QuestionParser.parse("❯ 1. A\n❯ 2. B") == nil)
    }

    @Test func usesTheLastWidgetOnScreen() throws {
        let pane = """
        Old question
        ❯ 1. Stale
          2. Answer

        New question
          1. Yes
        ❯ 2. No
        """
        let q = try #require(QuestionParser.parse(pane))
        #expect(q.text == "New question")
        #expect(q.pointer == 1)
    }
}
