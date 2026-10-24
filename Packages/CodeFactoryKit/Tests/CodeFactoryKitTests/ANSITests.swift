import Testing
@testable import CodeFactoryKit

@Suite struct ANSITests {
    @Test func plainTextIsOneRun() {
        #expect(ANSIParser.parse("hello") == [TerminalRun(text: "hello", style: TerminalStyle())])
    }

    @Test func colorsAndReset() {
        let runs = ANSIParser.parse("a\u{1B}[1;31mred\u{1B}[0m b")
        #expect(runs.map(\.text) == ["a", "red", " b"])
        #expect(runs[1].style.bold)
        #expect(runs[1].style.foreground == .indexed(1))
        #expect(runs[2].style == TerminalStyle())
    }

    @Test func extendedColors() {
        let runs = ANSIParser.parse("\u{1B}[38;5;208mo\u{1B}[48;2;1;2;3mx")
        #expect(runs[0].style.foreground == .palette(208))
        #expect(runs[1].style.background == .rgb(1, 2, 3))
        #expect(runs[1].style.foreground == .palette(208))
    }

    @Test func dropsNonSGRSequences() {
        #expect(ANSIParser.strip("\u{1B}]0;title\u{07}\u{1B}[2Kdone\u{1B}(B") == "done")
    }
}
