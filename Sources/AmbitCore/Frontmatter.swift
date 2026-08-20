import Foundation

/// Just enough YAML frontmatter reading to get `name` and `description` out of a SKILL.md or a
/// Claude subagent .md. Everything else in the file is irrelevant to inventory and is left alone.
public enum Frontmatter {
    public static func read(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return parse(text)
    }

    public static func parse(_ text: String) -> [String: String] {
        var lines = text.components(separatedBy: "\n")
        // Tolerate a UTF-8 BOM.
        if let first = lines.first, first.hasPrefix("\u{FEFF}") {
            lines[0] = String(first.dropFirst())
        }
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }

        var out: [String: String] = [:]
        var key: String?
        var buffer: [String] = []

        func flush() {
            if let key, !buffer.isEmpty {
                out[key] = buffer.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            }
            key = nil
            buffer = []
        }

        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            let isIndented = line.hasPrefix(" ") || line.hasPrefix("\t")
            if isIndented, key != nil {
                // Folded continuation of the previous scalar.
                buffer.append(line.trimmingCharacters(in: .whitespaces))
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            flush()
            key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty, rest != "|", rest != ">" { buffer = [unquote(rest)] }
        }
        flush()
        return out
    }

    static func unquote(_ s: String) -> String {
        if s.count >= 2, (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    /// Renders a minimal frontmatter block, used only when Adopt has to synthesise one.
    public static func render(name: String, description: String) -> String {
        "---\nname: \(name)\ndescription: \(description.replacingOccurrences(of: "\n", with: " "))\n---\n"
    }
}
