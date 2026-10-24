import Foundation

/// A terminal colour as SGR describes it; the app maps these onto a palette.
public enum TerminalColor: Hashable, Sendable {
    /// 0–15: the eight standard colours and their bright variants.
    case indexed(UInt8)
    /// 16–255 from the xterm 256-colour cube and grey ramp.
    case palette(UInt8)
    case rgb(UInt8, UInt8, UInt8)
}

public struct TerminalStyle: Hashable, Sendable {
    public var foreground: TerminalColor?
    public var background: TerminalColor?
    public var bold = false
    public var dim = false
    public var italic = false
    public var underline = false
    public var inverse = false
    public var strikethrough = false

    public init() {}
}

public struct TerminalRun: Hashable, Sendable {
    public var text: String
    public var style: TerminalStyle
}

/// Parses text with ANSI escape sequences into styled runs. SGR (colour and
/// emphasis) is interpreted; every other CSI/OSC sequence is dropped.
public enum ANSIParser {
    public static func parse(_ input: String) -> [TerminalRun] {
        var runs: [TerminalRun] = []
        var style = TerminalStyle()
        var buffer = ""
        let scalars = Array(input.unicodeScalars)
        var i = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            if let last = runs.last, last.style == style {
                runs[runs.count - 1].text += buffer
            } else {
                runs.append(TerminalRun(text: buffer, style: style))
            }
            buffer = ""
        }

        while i < scalars.count {
            let c = scalars[i]
            guard c == "\u{1B}" else {
                buffer.unicodeScalars.append(c)
                i += 1
                continue
            }
            guard i + 1 < scalars.count else { break }
            let kind = scalars[i + 1]
            if kind == "[" {
                // CSI: parameters, then a final byte in 0x40–0x7E.
                var j = i + 2
                var params = ""
                while j < scalars.count, !(0x40...0x7E).contains(scalars[j].value) {
                    params.unicodeScalars.append(scalars[j])
                    j += 1
                }
                if j < scalars.count, scalars[j] == "m" {
                    flush()
                    apply(params, to: &style)
                }
                i = j + 1
            } else if kind == "]" {
                // OSC: runs until BEL or ST (ESC \).
                var j = i + 2
                while j < scalars.count {
                    if scalars[j] == "\u{07}" { j += 1; break }
                    if scalars[j] == "\u{1B}", j + 1 < scalars.count, scalars[j + 1] == "\\" { j += 2; break }
                    j += 1
                }
                i = j
            } else if "()*+#%".unicodeScalars.contains(kind) {
                i += 3 // charset designation such as ESC ( B
            } else {
                i += 2 // other two-byte escapes such as ESC =
            }
        }
        flush()
        return runs
    }

    public static func strip(_ input: String) -> String {
        parse(input).map(\.text).joined()
    }

    static func apply(_ params: String, to style: inout TerminalStyle) {
        let codes = params.isEmpty ? [0] : params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        var k = 0
        while k < codes.count {
            let code = codes[k]
            switch code {
            case 0: style = TerminalStyle()
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 7: style.inverse = true
            case 9: style.strikethrough = true
            case 22: style.bold = false; style.dim = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 29: style.strikethrough = false
            case 30...37: style.foreground = .indexed(UInt8(code - 30))
            case 39: style.foreground = nil
            case 40...47: style.background = .indexed(UInt8(code - 40))
            case 49: style.background = nil
            case 90...97: style.foreground = .indexed(UInt8(code - 90 + 8))
            case 100...107: style.background = .indexed(UInt8(code - 100 + 8))
            case 38, 48:
                var color: TerminalColor?
                if k + 2 < codes.count, codes[k + 1] == 5 {
                    let n = UInt8(clamping: codes[k + 2])
                    color = n < 16 ? .indexed(n) : .palette(n)
                    k += 2
                } else if k + 4 < codes.count, codes[k + 1] == 2 {
                    color = .rgb(UInt8(clamping: codes[k + 2]), UInt8(clamping: codes[k + 3]), UInt8(clamping: codes[k + 4]))
                    k += 4
                }
                if code == 38 { style.foreground = color } else { style.background = color }
            default: break
            }
            k += 1
        }
    }
}
