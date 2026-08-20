import Foundation

/// A read-only TOML reader covering the subset Codex's `config.toml` uses, plus a
/// *line-surgical* writer that changes a single key inside a single table and leaves every
/// other byte — comments, ordering, formatting, unknown keys — exactly as it found it.
///
/// This is deliberately not a general TOML library. Anything it cannot confidently parse is
/// reported as an error so the caller refuses to write rather than guessing.
public enum TOML {

    // MARK: - Reading

    public indirect enum Value: Sendable, Equatable {
        case string(String)
        case integer(Int)
        case double(Double)
        case boolean(Bool)
        case array([Value])
        case table([String: Value])

        public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
        public var boolValue: Bool? { if case .boolean(let b) = self { return b }; return nil }
        public var tableValue: [String: Value]? { if case .table(let t) = self { return t }; return nil }
        public var arrayValue: [Value]? { if case .array(let a) = self { return a }; return nil }
    }

    /// Parses a document into nested tables. Only the shapes Codex writes are supported.
    public static func parse(_ text: String) throws -> [String: Value] {
        var root: [String: Value] = [:]
        var currentPath: [String] = []
        var scanner = LineScanner(text: text)

        while let raw = scanner.next() {
            let line = stripComment(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[[") {
                // Array-of-tables. Codex does not use these in config.toml; skip its body rather
                // than mis-modelling it, but keep parsing so the rest of the file still reads.
                currentPath = []
                continue
            }
            if line.hasPrefix("[") {
                guard line.hasSuffix("]") else { throw AmbitError.parse("Malformed table header: \(line)") }
                let inner = String(line.dropFirst().dropLast())
                currentPath = try parseKeyPath(inner)
                ensureTable(&root, path: currentPath)
                continue
            }

            guard let eq = indexOfTopLevelEquals(line) else {
                throw AmbitError.parse("Unrecognised TOML line: \(line)")
            }
            let keyText = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            var valueText = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)

            // A value may continue over several lines when it is a multi-line array or inline table.
            while needsMoreLines(valueText), let more = scanner.next() {
                valueText += "\n" + stripComment(more).trimmingCharacters(in: .whitespaces)
            }
            guard !needsMoreLines(valueText) else {
                throw AmbitError.parse("Unterminated value for key \(keyText).")
            }

            let keyPath = try parseKeyPath(keyText)
            let value = try parseValue(valueText)
            setValue(&root, path: currentPath + keyPath, value: value)
        }
        return root
    }

    public static func table(_ root: [String: Value], at path: [String]) -> [String: Value]? {
        var node: Value = .table(root)
        for component in path {
            guard let t = node.tableValue, let next = t[component] else { return nil }
            node = next
        }
        return node.tableValue
    }

    // MARK: - Minimal editing

    /// Sets (or clears) one bare key inside `[header]`, touching nothing else in the document.
    ///
    /// - Parameter value: rendered TOML value, or `nil` to delete the key.
    /// - Returns: the new document text.
    /// - Throws: when the table does not exist, so the caller never silently creates config.
    public static func setKey(
        _ key: String,
        to value: String?,
        inTable header: [String],
        document text: String
    ) throws -> String {
        var lines = text.components(separatedBy: "\n")
        guard let range = tableBodyRange(header: header, lines: lines) else {
            throw AmbitError.parse("Table [\(header.joined(separator: "."))] not found in config.")
        }

        // Look for an existing top-level assignment of `key` inside the table body.
        var existing: Int?
        var index = range.lowerBound
        while index < range.upperBound {
            let line = lines[index]
            let stripped = stripComment(line).trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty, let eq = indexOfTopLevelEquals(stripped) {
                let k = String(stripped[stripped.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
                if unquote(k) == key { existing = index }
                // Step over continuation lines of a multi-line value.
                var valueText = String(stripped[stripped.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                while needsMoreLines(valueText), index + 1 < range.upperBound {
                    index += 1
                    valueText += "\n" + stripComment(lines[index]).trimmingCharacters(in: .whitespaces)
                }
            }
            index += 1
        }

        if let existing {
            if let value {
                let indent = leadingWhitespace(lines[existing])
                lines[existing] = "\(indent)\(key) = \(value)"
            } else {
                lines.remove(at: existing)
            }
        } else if let value {
            // Insert directly under the header so the key lands in the right table no matter
            // what follows.
            lines.insert("\(key) = \(value)", at: range.lowerBound)
        }
        return lines.joined(separator: "\n")
    }

    /// Half-open line range covering `[header]` itself, its body, and any of its child tables.
    /// Used to lift a whole table out of a document, or to put one back verbatim.
    static func tableRegion(header: [String], lines: [String]) -> Range<Int>? {
        var start: Int?
        for (i, line) in lines.enumerated() {
            let stripped = stripComment(line).trimmingCharacters(in: .whitespaces)
            guard stripped.hasPrefix("["), stripped.hasSuffix("]") else { continue }
            let inner = stripped.hasPrefix("[[")
                ? String(stripped.dropFirst(2).dropLast(2))
                : String(stripped.dropFirst().dropLast())
            let path = (try? parseKeyPath(inner)) ?? []
            if let start {
                // A child table keeps the region open; anything else closes it.
                if path.count > header.count, Array(path.prefix(header.count)) == header { continue }
                return start..<i
            }
            if path == header { start = i }
        }
        return start.map { $0..<lines.count }
    }

    /// Removes `[header]` and everything under it, returning the new document and the exact text
    /// that was taken out so it can be restored byte-for-byte later.
    public static func removeTable(_ header: [String], from document: String) throws -> (document: String, removed: String) {
        var lines = document.components(separatedBy: "\n")
        guard var region = tableRegion(header: header, lines: lines) else {
            throw AmbitError.parse("Table [\(header.joined(separator: "."))] not found in config.")
        }
        let removed = lines[region].joined(separator: "\n")
        // Take the blank line that separated this table from the previous one, if there was one.
        if region.lowerBound > 0, lines[region.lowerBound - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            region = (region.lowerBound - 1)..<region.upperBound
        }
        lines.removeSubrange(region)
        return (lines.joined(separator: "\n"), removed)
    }

    /// Appends a rendered table to the end of a document.
    public static func appendTable(_ table: String, to document: String) -> String {
        var text = document
        while text.hasSuffix("\n") { text.removeLast() }
        if !text.isEmpty { text += "\n\n" }
        return text + table + "\n"
    }

    /// Renders a string value, preferring a readable multi-line literal when the content allows it.
    public static func renderPossiblyMultiline(_ s: String) -> String {
        let fence = String(repeating: "'", count: 3)
        guard s.contains("\n"), !s.contains(fence), !s.hasSuffix("'") else { return renderString(s) }
        return fence + "\n" + s + fence
    }

    /// Half-open line range of `[header]`'s body: the line after the header up to the next header.
    static func tableBodyRange(header: [String], lines: [String]) -> Range<Int>? {
        let wanted = header
        var start: Int?
        for (i, line) in lines.enumerated() {
            let stripped = stripComment(line).trimmingCharacters(in: .whitespaces)
            guard stripped.hasPrefix("["), !stripped.hasPrefix("[["), stripped.hasSuffix("]") else { continue }
            let path = (try? parseKeyPath(String(stripped.dropFirst().dropLast()))) ?? []
            if start != nil { return start!..<i }
            if path == wanted { start = i + 1 }
        }
        return start.map { $0..<lines.count }
    }

    public static func renderString(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out + "\""
    }

    // MARK: - Internals

    private struct LineScanner {
        let lines: [String]
        var index = 0
        init(text: String) { lines = text.components(separatedBy: "\n") }
        mutating func next() -> String? {
            guard index < lines.count else { return nil }
            defer { index += 1 }
            return lines[index]
        }
    }

    /// True when a value opened a bracket or brace it has not yet closed.
    static func needsMoreLines(_ text: String) -> Bool {
        var depth = 0
        var inString = false
        var escaped = false
        for ch in text {
            if escaped { escaped = false; continue }
            if ch == "\\" && inString { escaped = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            if inString { continue }
            if ch == "[" || ch == "{" { depth += 1 }
            if ch == "]" || ch == "}" { depth -= 1 }
        }
        return depth > 0
    }

    /// Drops a trailing `#` comment, respecting quotes.
    static func stripComment(_ line: String) -> String {
        var out = ""
        var inString = false
        var escaped = false
        for ch in line {
            if escaped { out.append(ch); escaped = false; continue }
            if ch == "\\" && inString { out.append(ch); escaped = true; continue }
            if ch == "\"" { inString.toggle(); out.append(ch); continue }
            if ch == "#" && !inString { break }
            out.append(ch)
        }
        return out
    }

    /// Index of the `=` that separates key from value, ignoring quoted sections.
    static func indexOfTopLevelEquals(_ line: String) -> String.Index? {
        var inString = false
        var escaped = false
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if escaped { escaped = false }
            else if ch == "\\" && inString { escaped = true }
            else if ch == "\"" { inString.toggle() }
            else if ch == "=" && !inString { return i }
            i = line.index(after: i)
        }
        return nil
    }

    static func parseKeyPath(_ text: String) throws -> [String] {
        var parts: [(value: String, quoted: Bool)] = []
        var current = ""
        var currentQuoted = false
        var inString = false
        var escaped = false
        for ch in text {
            if escaped { current.append(ch); escaped = false; continue }
            if ch == "\\" && inString { escaped = true; continue }
            if ch == "\"" || (ch == "'" && !inString && current.trimmingCharacters(in: .whitespaces).isEmpty) || (ch == "'" && inString) {
                inString.toggle()
                currentQuoted = true
                continue
            }
            if ch == "." && !inString {
                parts.append((current.trimmingCharacters(in: .whitespaces), currentQuoted))
                current = ""
                currentQuoted = false
                continue
            }
            current.append(ch)
        }
        guard !inString else { throw AmbitError.parse("Unterminated quoted TOML key: \(text)") }
        parts.append((current.trimmingCharacters(in: .whitespaces), currentQuoted))

        let cleaned = parts.filter { !$0.value.isEmpty || $0.quoted }
        guard !cleaned.isEmpty else { throw AmbitError.parse("Empty TOML key: \(text)") }
        // A bare key cannot contain spaces or punctuation. Rejecting them keeps a malformed
        // document from being silently reinterpreted as something we would then rewrite.
        for part in cleaned where !part.quoted {
            guard !part.value.isEmpty, part.value.allSatisfy(isBareKeyCharacter) else {
                throw AmbitError.parse("Invalid bare TOML key: \(text)")
            }
        }
        return cleaned.map(\.value)
    }

    static func isBareKeyCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "-"
    }

    static func unquote(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }

    static func leadingWhitespace(_ s: String) -> String {
        String(s.prefix { $0 == " " || $0 == "\t" })
    }

    static func parseValue(_ raw: String) throws -> Value {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\"\"\"") || text.hasPrefix("'''") {
            return .string(text) // Preserved verbatim; we never rewrite these.
        }
        if text.hasPrefix("\"") || text.hasPrefix("'") {
            return .string(unescape(unquote(text)))
        }
        if text == "true" { return .boolean(true) }
        if text == "false" { return .boolean(false) }
        if text.hasPrefix("[") {
            return .array(try parseArray(text))
        }
        if text.hasPrefix("{") {
            return .table(try parseInlineTable(text))
        }
        if let i = Int(text) { return .integer(i) }
        if let d = Double(text) { return .double(d) }
        // TOML dates and times are kept as literals so nothing is lost on read. Anything else is
        // a document we do not understand, and an unread document is never rewritten.
        let dateCharacters = Set("0123456789-:.+TZz ")
        guard !text.isEmpty, text.allSatisfy({ dateCharacters.contains($0) }) else {
            throw AmbitError.parse("Unrecognised TOML value: \(text)")
        }
        return .string(text)
    }

    static func unescape(_ s: String) -> String {
        var out = ""
        var escaped = false
        for ch in s {
            if escaped {
                switch ch {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\\": out.append("\\")
                case "\"": out.append("\"")
                default: out.append(ch)
                }
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else {
                out.append(ch)
            }
        }
        return out
    }

    static func splitTopLevel(_ body: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var inString = false
        var escaped = false
        for ch in body {
            if escaped { current.append(ch); escaped = false; continue }
            if ch == "\\" && inString { current.append(ch); escaped = true; continue }
            if ch == "\"" { inString.toggle(); current.append(ch); continue }
            if !inString {
                if ch == "[" || ch == "{" { depth += 1 }
                if ch == "]" || ch == "}" { depth -= 1 }
                if ch == "," && depth == 0 {
                    parts.append(current)
                    current = ""
                    continue
                }
            }
            current.append(ch)
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(current) }
        return parts
    }

    static func parseArray(_ text: String) throws -> [Value] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            throw AmbitError.parse("Malformed array: \(text)")
        }
        let body = String(trimmed.dropFirst().dropLast())
        return try splitTopLevel(body)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { try parseValue($0) }
    }

    static func parseInlineTable(_ text: String) throws -> [String: Value] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else {
            throw AmbitError.parse("Malformed inline table: \(text)")
        }
        var out: [String: Value] = [:]
        for pair in splitTopLevel(String(trimmed.dropFirst().dropLast())) {
            let entry = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            if entry.isEmpty { continue }
            guard let eq = indexOfTopLevelEquals(entry) else {
                throw AmbitError.parse("Malformed inline table entry: \(entry)")
            }
            let key = try parseKeyPath(String(entry[entry.startIndex..<eq]))
            let value = try parseValue(String(entry[entry.index(after: eq)...]))
            setValue(&out, path: key, value: value)
        }
        return out
    }

    static func ensureTable(_ root: inout [String: Value], path: [String]) {
        guard let head = path.first else { return }
        var child = root[head]?.tableValue ?? [:]
        if path.count > 1 { ensureTable(&child, path: Array(path.dropFirst())) }
        root[head] = .table(child)
    }

    static func setValue(_ root: inout [String: Value], path: [String], value: Value) {
        guard let head = path.first else { return }
        if path.count == 1 {
            root[head] = value
            return
        }
        var child = root[head]?.tableValue ?? [:]
        setValue(&child, path: Array(path.dropFirst()), value: value)
        root[head] = .table(child)
    }
}
