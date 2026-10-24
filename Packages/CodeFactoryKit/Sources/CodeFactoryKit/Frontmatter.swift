import Foundation

/// Minimal YAML-ish frontmatter support: flat `key: value` lines between
/// `---` fences at the very top of a file. Anything richer is preserved
/// byte-for-byte but not interpreted.
public struct Frontmatter: Sendable, Equatable {
    public var fields: [String: String]
    /// The document after the closing fence.
    public var body: String
    /// Whether the document had a frontmatter block at all.
    public var present: Bool

    public init(fields: [String: String] = [:], body: String, present: Bool) {
        self.fields = fields
        self.body = body
        self.present = present
    }

    private static var block: Regex<(Substring, Substring)> { /\A---\r?\n((?:.*\r?\n)*?)---(?:\r?\n|\z)/ }

    public static func parse(_ content: String) -> Frontmatter {
        guard let match = content.firstMatch(of: block) else {
            return Frontmatter(body: content, present: false)
        }
        var fields: [String: String] = [:]
        for line in match.1.split(whereSeparator: \.isNewline) {
            guard let kv = line.firstMatch(of: /^(\w[\w-]*):[ \t]*(.*)$/) else { continue }
            fields[String(kv.1)] = unquote(String(kv.2).trimmingCharacters(in: .whitespaces))
        }
        return Frontmatter(fields: fields, body: String(content[match.range.upperBound...]), present: true)
    }

    /// Rewrites (or inserts) the given keys inside the frontmatter block,
    /// leaving every other byte of the document untouched. Documents without
    /// frontmatter are returned unchanged.
    public static func updating(_ content: String, with changes: [String: String]) -> String {
        guard let match = content.firstMatch(of: block) else { return content }
        var lines = match.1.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        var pending = changes
        for index in lines.indices {
            guard let kv = lines[index].firstMatch(of: /^(\w[\w-]*):/) else { continue }
            let key = String(kv.1)
            if let value = pending.removeValue(forKey: key) {
                lines[index] = "\(key): \(value)"
            }
        }
        for key in pending.keys.sorted() {
            lines.append("\(key): \(pending[key]!)")
        }
        let rebuilt = "---\n" + lines.joined(separator: "\n") + "\n---\n"
        return rebuilt + content[match.range.upperBound...]
    }

    private static func unquote(_ value: String) -> String {
        for quote in ["\"", "'"] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
