import SwiftUI

/// A small block-level markdown renderer: headings, paragraphs, bullet,
/// numbered and task lists, quotes, code fences and rules. Inline styling is
/// delegated to `AttributedString(markdown:)`. Task boxes are clickable and
/// report the source line so the caller can toggle it in the file.
struct MarkdownView: View {
    let source: String
    var onToggleTask: ((Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.blocks(source).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    enum Block {
        case heading(Int, String)
        case paragraph(String)
        case bullet(String, indent: Int)
        case numbered(String, String, indent: Int)
        case task(Bool, String, line: Int, indent: Int)
        case quote(String)
        case code(String, language: String)
        case rule
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Self.inline(text)
                .font(level == 1 ? .title.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            Self.inline(text).fixedSize(horizontal: false, vertical: true)
        case .bullet(let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Self.inline(text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .numbered(let marker, let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).monospacedDigit().foregroundStyle(.secondary)
                Self.inline(text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .task(let done, let text, let line, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    onToggleTask?(line)
                } label: {
                    Image(systemName: done ? "checkmark.square.fill" : "square")
                        .foregroundStyle(done ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(onToggleTask == nil)
                Self.inline(text)
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(done ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.safetyOrange.opacity(0.7)).frame(width: 3)
                Self.inline(text).italic().foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        case .code(let code, let language):
            VStack(alignment: .leading, spacing: 4) {
                if !language.isEmpty {
                    Text(language.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code).font(.system(.callout, design: .monospaced))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        case .rule:
            Divider()
        }
    }

    static func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return Text(attributed)
        }
        return Text(text)
    }

    /// Splits a document body into blocks. `line` numbers in `.task` refer to
    /// the *full* source passed in, so callers can edit the original.
    static func blocks(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        var language = ""
        let lines = source.components(separatedBy: "\n")

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }

        for (number, raw) in lines.enumerated() {
            if var open = code {
                if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    blocks.append(.code(open.joined(separator: "\n"), language: language))
                    code = nil
                } else {
                    open.append(raw)
                    code = open
                }
                continue
            }
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.count / 2
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                flushParagraph()
                language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                code = []
            } else if line.isEmpty {
                flushParagraph()
            } else if let m = line.wholeMatch(of: /(#{1,6})\s+(.*)/) {
                flushParagraph()
                blocks.append(.heading(m.1.count, String(m.2)))
            } else if line.wholeMatch(of: /(-{3,}|\*{3,}|_{3,})/) != nil {
                flushParagraph()
                blocks.append(.rule)
            } else if let m = line.wholeMatch(of: /[-*+]\s+\[([ xX])\]\s*(.*)/) {
                flushParagraph()
                blocks.append(.task(m.1 != " ", String(m.2), line: number, indent: indent))
            } else if let m = line.wholeMatch(of: /[-*+]\s+(.*)/) {
                flushParagraph()
                blocks.append(.bullet(String(m.1), indent: indent))
            } else if let m = line.wholeMatch(of: /(\d+[.)])\s+(.*)/) {
                flushParagraph()
                blocks.append(.numbered(String(m.1), String(m.2), indent: indent))
            } else if line.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(line)
            }
        }
        if let open = code { blocks.append(.code(open.joined(separator: "\n"), language: language)) }
        flushParagraph()
        return blocks
    }

    /// Flips the checkbox on `line` of `source`.
    static func toggleTask(in source: String, line: Int) -> String {
        var lines = source.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return source }
        let current = lines[line]
        if let range = current.range(of: "[ ]") {
            lines[line] = current.replacingCharacters(in: range, with: "[x]")
        } else if let range = current.range(of: #"\[[xX]\]"#, options: .regularExpression) {
            lines[line] = current.replacingCharacters(in: range, with: "[ ]")
        }
        return lines.joined(separator: "\n")
    }
}
