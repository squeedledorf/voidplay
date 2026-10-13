import Foundation

// Rewrites upstream (macOS) Swift sources so they compile on Linux, where there is no
// Objective-C runtime:
//   #selector(Type.method(_:))  →  Selector("Type.method(_:)")
//   @objc / @objc(name) / @IBAction / @IBOutlet / dynamic  →  blanked
//   private/fileprivate on @objc methods  →  blanked (the registry calls them)
// and appends a function that registers every @objc method with SelectorRegistry, so menu
// items, notification observers and timers can call them by name.
// Edits never add or remove lines, so `#sourceLocation` keeps diagnostics on upstream lines.
//
// Usage: source-transform transform <input.swift> <output.swift> <id> [first-last]
//        source-transform registry <output.swift> <id>...

struct ObjCMethod {
    let typePath: String
    let name: String
    let params: [(label: String, type: String)]
    let throwing: Bool
}

final class Transformer {
    private let src: [UInt8]
    private var out: [UInt8] = []
    private var i = 0
    private(set) var methods: [ObjCMethod] = []

    /// Brace scopes: a type name for type bodies, nil for anything else.
    private var scopes: [String?] = []
    private var pendingType: String?

    init(_ text: String) { src = Array(text.utf8) }

    private func peek(_ offset: Int = 0) -> UInt8? { i + offset < src.count ? src[i + offset] : nil }
    private func at(_ s: String) -> Bool {
        let b = Array(s.utf8)
        return i + b.count <= src.count && Array(src[i..<i + b.count]) == b
    }
    private static func isIdent(_ c: UInt8) -> Bool {
        (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 95
    }
    private func boundaryBefore() -> Bool { i == 0 || !Self.isIdent(src[i - 1]) }

    private func copy(_ n: Int = 1) {
        out.append(contentsOf: src[i..<min(i + n, src.count)])
        i += n
    }

    private func blank(_ n: Int) {
        for k in 0..<n where i + k < src.count { out.append(src[i + k] == 10 ? 10 : 32) }
        i += n
    }

    func run() -> String {
        while i < src.count {
            if at("//") { copyLineComment(); continue }
            if at("/*") { copyBlockComment(); continue }
            if at("#\"") || at("##\"") { copyRawString(); continue }
            if at("\"\"\"") { copyMultilineString(); continue }
            if peek() == 34 { copyString(); continue }
            if at("#selector("), boundaryBefore() { rewriteSelector(); continue }
            if peek() == 64 /* @ */ { if handleAttribute() { continue } }
            if Self.isIdent(src[i]), boundaryBefore() { handleWord(); continue }
            if peek() == 123 /* { */ { scopes.append(pendingType); pendingType = nil; copy(); continue }
            if peek() == 125 /* } */ { _ = scopes.popLast(); copy(); continue }
            if peek() == 59 /* ; */ { pendingType = nil }
            copy()
        }
        return String(decoding: out, as: UTF8.self)
    }

    // MARK: Literals and comments (copied verbatim)

    private func copyLineComment() { while i < src.count, src[i] != 10 { copy() } }

    private func copyBlockComment() {
        var depth = 0
        repeat {
            if at("/*") { depth += 1; copy(2) } else if at("*/") { depth -= 1; copy(2) } else { copy() }
        } while depth > 0 && i < src.count
    }

    private func copyString() {
        copy()
        while i < src.count {
            if src[i] == 92 { copy(2); continue }
            if src[i] == 40, i > 0, src[i - 1] == 92 { copy(); continue }
            if src[i] == 34 || src[i] == 10 { copy(); return }
            if at("\\(") { copyInterpolation(); continue }
            copy()
        }
    }

    private func copyInterpolation() {
        copy(2)
        var depth = 1
        while i < src.count, depth > 0 {
            if peek() == 34 { copyString(); continue }
            if src[i] == 40 { depth += 1 } else if src[i] == 41 { depth -= 1 }
            copy()
        }
    }

    private func copyMultilineString() {
        copy(3)
        while i < src.count, !at("\"\"\"") {
            if src[i] == 92 { if at("\\(") { copyInterpolation() } else { copy(2) }; continue }
            copy()
        }
        copy(3)
    }

    private func copyRawString() {
        var hashes = 0
        while peek() == 35 { hashes += 1; copy() }
        let multi = at("\"\"\"")
        copy(multi ? 3 : 1)
        let close = (multi ? "\"\"\"" : "\"") + String(repeating: "#", count: hashes)
        while i < src.count, !at(close) { copy() }
        copy(close.utf8.count)
    }

    // MARK: Rewrites

    private func rewriteSelector() {
        let start = i
        i += "#selector(".utf8.count
        var depth = 1
        var inner: [UInt8] = []
        var newlines = 0
        while i < src.count, depth > 0 {
            let c = src[i]
            if c == 40 { depth += 1 } else if c == 41 { depth -= 1; if depth == 0 { break } }
            if c == 10 { newlines += 1 } else if c != 32 && c != 9 { inner.append(c) }
            i += 1
        }
        i += 1  // closing paren
        _ = start
        out.append(contentsOf: Array("Selector(\"".utf8) + inner + Array("\")".utf8))
        out.append(contentsOf: [UInt8](repeating: 10, count: newlines))
    }

    private static let blankedAttributes = ["@objcMembers", "@objc", "@IBAction", "@IBOutlet", "@IBInspectable",
                                            "@IBDesignable", "@NSManaged"]

    /// Blanks Objective-C attributes; for @objc methods also records them and drops private.
    private func handleAttribute() -> Bool {
        guard let attribute = Self.blankedAttributes.first(where: { at($0) && !(peek($0.utf8.count).map(Self.isIdent) ?? false) })
        else { return false }
        blank(attribute.utf8.count)
        if peek() == 40 {  // @objc(selectorName)
            var depth = 0
            repeat {
                if src[i] == 40 { depth += 1 } else if src[i] == 41 { depth -= 1 }
                blank(1)
            } while depth > 0 && i < src.count
        }
        if attribute == "@objc" || attribute == "@IBAction" { scanObjCDeclaration() }
        return true
    }

    /// After an @objc attribute: blank access modifiers up to `func`, and record the method.
    private func scanObjCDeclaration() {
        let modifiers: Set<String> = ["private", "fileprivate", "public", "internal", "open", "override", "final",
                                      "static", "class", "dynamic", "required", "convenience", "nonisolated",
                                      "@MainActor", "mutating"]
        var j = i
        var blanks: [(Int, Int)] = []
        var isStatic = false
        while j < src.count {
            while j < src.count, src[j] == 32 || src[j] == 9 || src[j] == 10 { j += 1 }
            if j < src.count, src[j] == 64 {  // another attribute, e.g. @MainActor
                var k = j + 1
                while k < src.count, Self.isIdent(src[k]) { k += 1 }
                j = k
                continue
            }
            var k = j
            while k < src.count, Self.isIdent(src[k]) { k += 1 }
            let word = String(decoding: src[j..<k], as: UTF8.self)
            if word == "private" || word == "fileprivate" {
                var end = k
                if end < src.count, src[end] == 40 { while end < src.count, src[end] != 41 { end += 1 }; end += 1 }
                blanks.append((j, end))
                j = end
                continue
            }
            if word == "static" || word == "class" { isStatic = true }
            if modifiers.contains(word) { j = k; continue }
            if word == "func" { recordMethod(from: k, isStatic: isStatic) }
            break
        }
        for (start, end) in blanks where start >= i {
            for p in start..<end { srcBlank.insert(p) }
        }
    }

    /// Positions to emit as spaces when copied (modifiers found by look-ahead).
    private var srcBlank = Set<Int>()

    private func recordMethod(from position: Int, isStatic: Bool) {
        guard !isStatic, let typePath = currentTypePath else { return }
        var j = position
        while j < src.count, src[j] == 32 { j += 1 }
        var k = j
        while k < src.count, Self.isIdent(src[k]) { k += 1 }
        let name = String(decoding: src[j..<k], as: UTF8.self)
        guard !name.isEmpty, k < src.count, src[k] == 40 else { return }
        var depth = 0
        var end = k
        repeat {
            if src[end] == 40 { depth += 1 } else if src[end] == 41 { depth -= 1 }
            end += 1
        } while depth > 0 && end < src.count
        let paramText = String(decoding: src[(k + 1)..<(end - 1)], as: UTF8.self)
        var tail = end
        while tail < src.count, src[tail] != 123, src[tail] != 10 { tail += 1 }
        let effects = String(decoding: src[end..<tail], as: UTF8.self)
        guard !effects.contains("async") else { return }
        methods.append(ObjCMethod(typePath: typePath, name: name, params: Self.parseParams(paramText),
                                  throwing: effects.contains("throws")))
    }

    private static func parseParams(_ text: String) -> [(label: String, type: String)] {
        var params: [String] = []
        var depth = 0
        var current = ""
        for ch in text {
            if "([<".contains(ch) { depth += 1 } else if ")]>".contains(ch) { depth -= 1 }
            if ch == ",", depth == 0 { params.append(current); current = "" } else { current.append(ch) }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { params.append(current) }
        return params.compactMap { p in
            let parts = p.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let names = parts[0].split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            var type = String(parts[1])
            if let eq = type.firstIndex(of: "=") { type = String(type[..<eq]) }
            type = type.trimmingCharacters(in: .whitespacesAndNewlines)
            return (label: String(names.first ?? "_"), type: type)
        }
    }

    private var currentTypePath: String? {
        guard !scopes.isEmpty, scopes.allSatisfy({ $0 != nil }) else { return nil }
        return scopes.compactMap { $0 }.joined(separator: ".")
    }

    private static let typeKeywords: Set<String> = ["class", "struct", "enum", "extension", "actor"]
    private static let notTypeNames: Set<String> = ["func", "var", "let", "subscript", "init", "deinit", "override",
                                                    "private", "fileprivate", "public", "internal", "open", "final",
                                                    "static", "required", "convenience", "case", "protocol"]

    private func handleWord() {
        var k = i
        while k < src.count, Self.isIdent(src[k]) { k += 1 }
        let word = String(decoding: src[i..<k], as: UTF8.self)
        if word == "dynamic" {
            // Blank `dynamic` only as a declaration modifier.
            var j = k
            while j < src.count, src[j] == 32 { j += 1 }
            var e = j
            while e < src.count, Self.isIdent(src[e]) { e += 1 }
            let next = String(decoding: src[j..<e], as: UTF8.self)
            if ["var", "func", "let", "private", "fileprivate", "public", "internal", "open", "override", "final", "weak", "lazy"].contains(next) {
                blank(k - i)
                return
            }
        }
        if Self.typeKeywords.contains(word) || word == "protocol" {
            var j = k
            while j < src.count, src[j] == 32 { j += 1 }
            var e = j
            while e < src.count, Self.isIdent(src[e]) || src[e] == 46 { e += 1 }
            let name = String(decoding: src[j..<e], as: UTF8.self)
            if !name.isEmpty, !Self.notTypeNames.contains(name) {
                // Generic types and protocols cannot be cast to by name; their methods are not registered.
                let generic = e < src.count && src[e] == 60
                pendingType = (word == "protocol" || generic) ? nil : name
            }
        }
        while i < k {
            if srcBlank.contains(i) { blank(1) } else { copy() }
        }
    }
}

// MARK: - Registry code

func identifier(_ id: String) -> String { "_voidplaySelectors_" + id }

func registrationCode(id: String, methods: [ObjCMethod]) -> String {
    var lines = ["", "#sourceLocation()", "func \(identifier(id))() {"]
    for m in methods {
        var call: String
        var guards = ""
        switch m.params.count {
        case 0:
            call = "target.\(m.name)()"
        case 1:
            let p = m.params[0]
            let label = p.label == "_" ? "" : "\(p.label): "
            let type = p.type.replacingOccurrences(of: "@escaping ", with: "")
            let arg: String
            if type == "Any?" { arg = "sender" }
            else if type == "Any" { arg = "sender as Any" }
            else if type.hasSuffix("?") { arg = "sender as? \(type.dropLast())" }
            else if type.contains("->") || type.contains("inout") { continue }
            else { guards = " guard let sender = sender as? \(type) else { return false };"; arg = "sender" }
            call = "target.\(m.name)(\(label)\(arg))"
        default:
            continue
        }
        lines.append("    SelectorRegistry.register(\"\(m.name)\", type: \"\(m.typePath)\") { target, sender in")
        let invoke = m.throwing ? "try? \(call)" : call
        lines.append("        guard let target = target as? \(m.typePath) else { return false };\(guards) _ = \(invoke); return true")
        lines.append("    }")
    }
    lines.append("}")
    return lines.joined(separator: "\n") + "\n"
}

// MARK: - Entry

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "transform" where args.count == 5 || args.count == 6:
    let input = URL(fileURLWithPath: args[2])
    var text = try String(contentsOf: input, encoding: .utf8)
    // Optional "first-last" line range: compile only that slice of a large upstream file.
    var firstLine = 1
    var imports: [String] = []
    if args.count == 6 {
        let bounds = args[5].split(separator: "-").compactMap { Int($0) }
        guard bounds.count == 2, bounds[0] >= 1, bounds[1] >= bounds[0] else {
            FileHandle.standardError.write(Data("bad line range \(args[5])\n".utf8)); exit(2)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        imports = lines.filter { $0.hasPrefix("import ") }.map(String.init)
        text = lines[(bounds[0] - 1)..<min(bounds[1], lines.count)].joined(separator: "\n")
        firstLine = bounds[0]
    }
    // Apple submodule imports (`import os.lock`) name a Swift stand-in module here.
    text = text.replacingOccurrences(of: "import os.lock", with: "import os     ")
    let transformer = Transformer(text)
    var body = transformer.run()
    if !body.hasSuffix("\n") { body += "\n" }
    // A slice keeps its file's imports (which may sit outside the slice).
    let header = (firstLine > 1 ? imports.joined(separator: "\n") + "\n" : "")
        + "#sourceLocation(file: \"\(input.path)\", line: \(firstLine))\n"
    try (header + body + registrationCode(id: args[4], methods: transformer.methods))
        .write(to: URL(fileURLWithPath: args[3]), atomically: true, encoding: .utf8)
case "registry" where args.count >= 3:
    let calls = args.dropFirst(3).map { "    \(identifier($0))()" }.joined(separator: "\n")
    let code = "/// Generated: registers every @objc method of the transformed upstream sources.\n" +
        "func registerUpstreamSelectors() {\n\(calls)\n}\n"
    try code.write(to: URL(fileURLWithPath: args[2]), atomically: true, encoding: .utf8)
default:
    FileHandle.standardError.write(Data("usage: source-transform transform <in> <out> <id> | registry <out> <id>...\n".utf8))
    exit(2)
}
