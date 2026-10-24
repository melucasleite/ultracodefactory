import Foundation

/// A multiple-choice prompt Claude Code is showing in its TUI —
/// AskUserQuestion, permission prompts, anything drawn as a numbered option
/// list with a `❯` pointer on the highlighted row.
public struct PaneQuestion: Equatable, Sendable {
    public struct Option: Equatable, Sendable, Identifiable {
        public var number: Int
        public var label: String
        public var pointed: Bool
        public var checked: Bool
        public var id: Int { number }
    }

    public var text: String
    public var options: [Option]
    /// Index into `options` of the row the TUI cursor is on.
    public var pointer: Int
    public var multiSelect: Bool

    /// The keystrokes that move the cursor to `index` and pick it.
    public func keys(toChoose index: Int) -> [NamedKey] {
        let delta = index - pointer
        let arrows = Array(repeating: delta > 0 ? NamedKey.down : .up, count: abs(delta))
        return arrows + [multiSelect ? .space : .enter]
    }
}

/// Heuristic, deliberately conservative parser for those prompts. Anything
/// that does not match cleanly yields `nil` and the console falls back to
/// the raw terminal — a wrong parse must never send stray keystrokes.
public enum QuestionParser {
    private static var optionLine: Regex<(Substring, pointer: Substring?, mark: Substring?, number: Substring, label: Substring)> {
        /^\s*(?<pointer>❯|›)?\s*(?<mark>◉|○|◯|●|☐|☒|\[[ xX✓]\])?\s*(?<number>\d{1,2})[.)]\s+(?<label>.+?)\s*$/
    }

    public static func parse(_ pane: String) -> PaneQuestion? {
        let lines = pane.components(separatedBy: "\n").map(stripBorders)

        struct Hit { var line: Int; var number: Int; var label: String; var pointed: Bool; var mark: String? }
        var hits: [Hit] = []
        let pattern = optionLine
        for (index, line) in lines.enumerated() {
            guard let m = line.wholeMatch(of: pattern), let number = Int(m.number) else { continue }
            hits.append(Hit(
                line: index,
                number: number,
                label: String(m.label),
                pointed: m.pointer != nil,
                mark: m.mark.map(String.init)
            ))
        }
        guard hits.count >= 2 else { return nil }

        // The live widget sits at the bottom of the pane: walk back from the
        // last hit collecting a consecutive N…1 run (descriptions may sit
        // between rows, so line gaps are fine).
        var block: [Hit] = []
        var end = hits.count - 1
        while end >= 0 {
            var run = [hits[end]]
            var want = hits[end].number - 1
            var j = end - 1
            while j >= 0, want >= 1 {
                if hits[j].number == want {
                    run.insert(hits[j], at: 0)
                    want -= 1
                }
                j -= 1
            }
            if want == 0, run.first?.number == 1, run.count >= 2 {
                block = run
                break
            }
            end -= 1
        }
        guard !block.isEmpty else { return nil }

        // A real selector has exactly one pointer row; numbered lists in
        // ordinary prose have none. This is the false-positive gate.
        let pointed = block.indices.filter { block[$0].pointed }
        guard pointed.count == 1, let pointer = pointed.first else { return nil }

        let multiSelect = block.contains { $0.mark != nil && $0.mark != "●" }
        let options = block.map { hit in
            PaneQuestion.Option(
                number: hit.number,
                label: hit.label,
                pointed: hit.pointed,
                checked: ["◉", "☒", "●"].contains(hit.mark ?? "") || (hit.mark?.contains(where: { "xX✓".contains($0) }) ?? false)
            )
        }

        // Question text: the nearest non-blank lines above the block.
        var textLines: [String] = []
        var i = block[0].line - 1
        while i >= 0, textLines.count < 2 {
            let clean = lines[i]
                .trimmingCharacters(in: CharacterSet(charactersIn: "●⏺✳✻·※☐ ").union(.whitespaces))
            if clean.isEmpty {
                if !textLines.isEmpty { break }
            } else {
                textLines.insert(clean, at: 0)
            }
            i -= 1
        }

        return PaneQuestion(
            text: textLines.isEmpty ? "Choose an option" : textLines.joined(separator: " — "),
            options: options,
            pointer: pointer,
            multiSelect: multiSelect
        )
    }

    /// Strips the box-drawing borders tmux capture leaves around widgets.
    static func stripBorders(_ line: String) -> String {
        let leading = CharacterSet(charactersIn: "│┃╭╰├ \t")
        let trailing = CharacterSet(charactersIn: "│┃╮╯┤─ \t")
        var scalars = Substring.UnicodeScalarView(line.unicodeScalars)
        while let first = scalars.first, leading.contains(first) { scalars.removeFirst() }
        while let last = scalars.last, trailing.contains(last) { scalars.removeLast() }
        return String(scalars)
    }
}
