import Foundation

/// Edits one top-level key of a JSON document **as text**, leaving every other byte exactly as it
/// was found.
///
/// The obvious approach — parse to `[String: Any]`, change one key, re-serialise — is not safe on a
/// file like `~/.claude.json`. Foundation reorders every key and its number formatter does not
/// round-trip doubles exactly (`0.06962500000008731` comes back as `0.069625000000087311`), so a
/// one-key edit would silently rewrite thousands of unrelated bytes. Here the only bytes that move
/// are the ones between the target key and the end of its value.
public enum JSONTextEditor {

    /// - Parameter value: the replacement value, or `nil` to remove the key.
    public static func setTopLevelValue(_ value: Any?, forKey key: String, in text: String) throws -> String {
        let characters = Array(text)
        guard let root = try locateTopLevelObject(characters) else {
            // No document yet: write a fresh one rather than failing.
            guard let value else { return text }
            return try render(["\(key)": value])
        }

        let members = try scanMembers(characters, from: root.contentStart, to: root.contentEnd)
        let target = members.first { $0.key == key }

        if let target {
            guard let value else { return remove(target, from: members, characters: characters) }
            let indent = indentation(before: target.keyStart, in: characters)
            let rendered = try renderValue(value, indentedBy: indent)
            return String(characters[..<target.valueStart]) + rendered + String(characters[target.valueEnd...])
        }

        guard let value else { return text }
        return try insert(key: key, value: value, characters: characters, root: root, members: members)
    }

    // MARK: - Structure

    private struct Member {
        var key: String
        var keyStart: Int
        var valueStart: Int
        var valueEnd: Int
    }

    private struct Root {
        var contentStart: Int
        var contentEnd: Int
    }

    private static func locateTopLevelObject(_ c: [Character]) throws -> Root? {
        var i = skipWhitespace(c, 0)
        guard i < c.count else { return nil }
        guard c[i] == "{" else { throw SkillswitchError.parse("Expected a JSON object at the top level.") }
        i += 1
        var end = c.count - 1
        while end > i, c[end].isWhitespace { end -= 1 }
        guard end >= i, c[end] == "}" else { throw SkillswitchError.parse("Unterminated JSON object.") }
        return Root(contentStart: i, contentEnd: end)
    }

    private static func scanMembers(_ c: [Character], from start: Int, to end: Int) throws -> [Member] {
        var members: [Member] = []
        var i = start
        while true {
            i = skipWhitespace(c, i)
            if i >= end { break }
            if c[i] == "," { i += 1; continue }
            guard c[i] == "\"" else { throw SkillswitchError.parse("Expected a JSON key at offset \(i).") }
            let keyStart = i
            let (key, afterKey) = try readString(c, i)
            i = skipWhitespace(c, afterKey)
            guard i < end, c[i] == ":" else { throw SkillswitchError.parse("Expected ':' after key \"\(key)\".") }
            i = skipWhitespace(c, i + 1)
            let valueStart = i
            i = try skipValue(c, i)
            members.append(Member(key: key, keyStart: keyStart, valueStart: valueStart, valueEnd: i))
        }
        return members
    }

    // MARK: - Editing

    private static func remove(_ target: Member, from members: [Member], characters c: [Character]) -> String {
        var cutStart = target.keyStart
        var cutEnd = target.valueEnd

        if let index = members.firstIndex(where: { $0.keyStart == target.keyStart }) {
            if index + 1 < members.count {
                // Take the comma and whitespace that separate this member from the next one.
                var j = cutEnd
                while j < members[index + 1].keyStart, c[j] != "," { j += 1 }
                if j < c.count, c[j] == "," { cutEnd = j + 1 }
            } else if index > 0 {
                // Last member: take the preceding comma instead so the object stays valid.
                var j = cutStart - 1
                while j > members[index - 1].valueEnd, c[j] != "," { j -= 1 }
                if j >= 0, c[j] == "," { cutStart = j }
            }
        }
        // Swallow the now-empty line this leaves behind.
        while cutStart > 0, c[cutStart - 1] == " " || c[cutStart - 1] == "\t" { cutStart -= 1 }
        if cutStart > 0, c[cutStart - 1] == "\n" { cutStart -= 1 }

        return String(c[..<cutStart]) + String(c[cutEnd...])
    }

    private static func insert(
        key: String, value: Any, characters c: [Character], root: Root, members: [Member]
    ) throws -> String {
        let indent = members.first.map { indentation(before: $0.keyStart, in: c) } ?? "  "
        let rendered = try renderValue(value, indentedBy: indent)
        let entry = "\(indent)\(renderKey(key)): \(rendered)"

        guard let last = members.last else {
            return String(c[..<root.contentStart]) + "\n" + entry + "\n" + String(c[root.contentEnd...])
        }
        return String(c[..<last.valueEnd]) + ",\n" + entry + String(c[last.valueEnd...])
    }

    // MARK: - Rendering

    private static func render(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw SkillswitchError.io("Could not encode JSON.") }
        return text + "\n"
    }

    /// Pretty-prints a value and re-indents its continuation lines to sit under `indent`.
    private static func renderValue(_ value: Any, indentedBy indent: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw SkillswitchError.io("Could not encode JSON value.") }
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return text }
        return ([lines[0]] + lines.dropFirst().map { indent + $0 }).joined(separator: "\n")
    }

    private static func renderKey(_ key: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [key], options: [.withoutEscapingSlashes])
        guard let data, let text = String(data: data, encoding: .utf8) else { return "\"\(key)\"" }
        return String(text.dropFirst().dropLast()) // strip the array brackets
    }

    // MARK: - Lexing

    private static func skipWhitespace(_ c: [Character], _ start: Int) -> Int {
        var i = start
        while i < c.count, c[i].isWhitespace { i += 1 }
        return i
    }

    private static func indentation(before position: Int, in c: [Character]) -> String {
        var start = position
        while start > 0, c[start - 1] == " " || c[start - 1] == "\t" { start -= 1 }
        return String(c[start..<position])
    }

    private static func readString(_ c: [Character], _ start: Int) throws -> (String, Int) {
        var i = start + 1
        var out = ""
        while i < c.count {
            let ch = c[i]
            if ch == "\\" {
                guard i + 1 < c.count else { break }
                let next = c[i + 1]
                switch next {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "b": out.append("\u{08}")
                case "f": out.append("\u{0C}")
                case "u":
                    guard i + 5 < c.count, let scalar = UInt32(String(c[(i + 2)...(i + 5)]), radix: 16),
                          let unicode = Unicode.Scalar(scalar) else { throw SkillswitchError.parse("Bad \\u escape in JSON key.") }
                    out.unicodeScalars.append(unicode)
                    i += 4
                default: out.append(next)
                }
                i += 2
                continue
            }
            if ch == "\"" { return (out, i + 1) }
            out.append(ch)
            i += 1
        }
        throw SkillswitchError.parse("Unterminated JSON string.")
    }

    private static func skipValue(_ c: [Character], _ start: Int) throws -> Int {
        var i = start
        guard i < c.count else { throw SkillswitchError.parse("Missing JSON value.") }
        switch c[i] {
        case "\"":
            return try readString(c, i).1
        case "{", "[":
            var depth = 0
            while i < c.count {
                let ch = c[i]
                if ch == "\"" { i = try readString(c, i).1; continue }
                if ch == "{" || ch == "[" { depth += 1 }
                if ch == "}" || ch == "]" {
                    depth -= 1
                    if depth == 0 { return i + 1 }
                }
                i += 1
            }
            throw SkillswitchError.parse("Unterminated JSON container.")
        default:
            while i < c.count, !",}]".contains(c[i]), !c[i].isWhitespace { i += 1 }
            guard i > start else { throw SkillswitchError.parse("Empty JSON value at offset \(start).") }
            return i
        }
    }
}
