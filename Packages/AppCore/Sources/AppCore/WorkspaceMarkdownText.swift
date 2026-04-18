import Foundation
import MarkdownUI
import SwiftUI

public enum WorkspaceMarkdownSourceFormatter {
    public static func normalized(_ text: String) -> String {
        let value = WorkspaceStringTransformCache.normalized.value(for: text) {
            normalizedUncached($0)
        }
        return value
    }

    private static func normalizedUncached(_ text: String) -> String {
        let normalizedLineEndings = text.replacingOccurrences(of: "\r\n", with: "\n")
        let unwrappedMarkdownFence = unwrapMarkdownExampleFence(in: normalizedLineEndings)
        let lines = unwrappedMarkdownFence.components(separatedBy: "\n")
        guard lines.isEmpty == false else {
            return unwrappedMarkdownFence
        }

        var result: [String] = []
        result.reserveCapacity(lines.count)

        var index = 0
        while index < lines.count {
            let line = lines[index]
            if shouldDedentMarkdownBlock(startingAt: index, in: lines) {
                let end = endIndexForIndentedBlock(startingAt: index, in: lines)
                let block = Array(lines[index..<end])
                let indent = commonIndentation(in: block)
                result.append(contentsOf: block.map { dedent($0, by: indent) })
                index = end
                continue
            }

            result.append(line)
            index += 1
        }

        return result.joined(separator: "\n")
    }

    private static func unwrapMarkdownExampleFence(in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.isEmpty == false,
              let openingFenceIndex = lines.firstIndex(where: isMarkdownExampleFenceOpening),
              let closingFenceIndex = lines.indices.reversed().first(where: { index in
                  index > openingFenceIndex && isPlainFence(lines[index])
              }) else {
            return text
        }

        let fencedLines = Array(lines[(openingFenceIndex + 1)..<closingFenceIndex])
        let markdownSignalCount = fencedLines.reduce(into: 0) { count, line in
            if looksLikeMarkdownLine(line) {
                count += 1
            }
        }
        guard markdownSignalCount >= 3 else {
            return text
        }

        var rebuilt: [String] = []
        rebuilt.reserveCapacity(lines.count - 2)
        rebuilt.append(contentsOf: lines[..<openingFenceIndex])
        rebuilt.append(contentsOf: fencedLines)
        if closingFenceIndex + 1 < lines.count {
            rebuilt.append(contentsOf: lines[(closingFenceIndex + 1)...])
        }
        return rebuilt.joined(separator: "\n")
    }

    private static func shouldDedentMarkdownBlock(startingAt start: Int, in lines: [String]) -> Bool {
        let end = endIndexForIndentedBlock(startingAt: start, in: lines)
        let block = Array(lines[start..<end])
        let nonEmpty = block.filter { $0.trimmingCharacters(in: .whitespaces).isEmpty == false }
        guard nonEmpty.count >= 3 else {
            return false
        }

        let commonIndent = commonIndentation(in: block)
        guard commonIndent >= 4 else {
            return false
        }

        let markerCount = nonEmpty.reduce(into: 0) { count, line in
            if looksLikeMarkdownLine(dedent(line, by: commonIndent)) {
                count += 1
            }
        }

        return markerCount >= 2
    }

    private static func endIndexForIndentedBlock(startingAt start: Int, in lines: [String]) -> Int {
        var index = start
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }
            if leadingIndentation(of: line) < 4 {
                break
            }
            index += 1
        }
        return index
    }

    private static func commonIndentation(in lines: [String]) -> Int {
        lines
            .filter { $0.trimmingCharacters(in: .whitespaces).isEmpty == false }
            .map(leadingIndentation(of:))
            .min() ?? 0
    }

    private static func leadingIndentation(of line: String) -> Int {
        var count = 0
        for character in line {
            switch character {
            case " ":
                count += 1
            case "\t":
                count += 4
            default:
                return count
            }
        }
        return count
    }

    private static func dedent(_ line: String, by width: Int) -> String {
        guard width > 0, line.isEmpty == false else {
            return line
        }

        var remaining = width
        var index = line.startIndex
        while index < line.endIndex, remaining > 0 {
            switch line[index] {
            case " ":
                remaining -= 1
                index = line.index(after: index)
            case "\t":
                remaining -= min(4, remaining)
                index = line.index(after: index)
            default:
                return String(line[index...])
            }
        }
        return String(line[index...])
    }

    private static func looksLikeMarkdownLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false else {
            return false
        }

        let patterns = [
            #"^#{1,6}\s"#,
            #"^[-*+]\s"#,
            #"^\d+\.\s"#,
            #"^>\s"#,
            #"^```"#,
            #"^\[(?: |x|X)\]\s"#,
            #"\[[^\]]+\]\([^)]+\)"#,
            #"\*\*.+\*\*"#,
            #"\*[^*\n]+\*"#,
            #"~~.+~~"#,
            #"`[^`\n]+`"#,
            #"^\|.+\|$"#
        ]

        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return false
            }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            return regex.firstMatch(in: trimmed, options: [], range: range) != nil
        }
    }

    private static func isMarkdownExampleFenceOpening(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "```markdown" || trimmed == "```md"
    }

    private static func isPlainFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "```"
    }
}

public enum WorkspaceMarkdownPreviewFormatter {
    public static func plainText(_ text: String) -> String {
        let value = WorkspaceStringTransformCache.preview.value(for: text) {
            plainTextUncached($0)
        }
        return value
    }

    private static func plainTextUncached(_ text: String) -> String {
        let normalized = WorkspaceMarkdownSourceFormatter.normalized(text)
        guard normalized.isEmpty == false else {
            return normalized
        }

        var sanitized = normalized
        sanitized = replace(#"(?m)^```[^\n]*\n?"#, in: sanitized, with: "")
        sanitized = replace(#"(?m)^```$"#, in: sanitized, with: "")
        sanitized = replace(#"!\[([^\]]*)\]\([^)]+\)"#, in: sanitized, with: "$1")
        sanitized = replace(#"\[([^\]]+)\]\([^)]+\)"#, in: sanitized, with: "$1")
        sanitized = replace(#"(?m)^#{1,6}\s+"#, in: sanitized, with: "")
        sanitized = replace(#"(?m)^\s*>\s?"#, in: sanitized, with: "")
        sanitized = replace(#"(?m)^\s*(?:[-*+]|\d+\.)\s+"#, in: sanitized, with: "")
        sanitized = replace(#"(?m)^\s*\[(?: |x|X)\]\s+"#, in: sanitized, with: "")
        sanitized = replace(#"[`*_~]+"#, in: sanitized, with: "")
        sanitized = sanitized.replacingOccurrences(of: "|", with: " ")

        return sanitized
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}

public enum WorkspaceMarkdownRenderMode: Equatable, Sendable {
  case plainText
  case markdown

  public static func resolve(
    for text: String,
    isStreaming: Bool,
    prefersMarkdown: Bool = false
  ) -> WorkspaceMarkdownRenderMode {
    let normalized = WorkspaceMarkdownSourceFormatter.normalized(text)
    return resolveNormalized(
        for: normalized,
        isStreaming: isStreaming,
        prefersMarkdown: prefersMarkdown
    )
  }

  public static func resolveNormalized(
    for text: String,
    isStreaming: Bool,
    prefersMarkdown: Bool = false
  ) -> WorkspaceMarkdownRenderMode {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else {
      return .plainText
    }

    if isStreaming, looksLikeIncompleteMarkdown(trimmed) {
      return .plainText
    }

    if prefersMarkdown {
      return .markdown
    }

    return looksLikeMarkdown(trimmed) ? .markdown : .plainText
  }

    static func looksLikeMarkdown(_ text: String) -> Bool {
        let markers = [
            "\n#",
            "\n##",
            "\n###",
            "\n- ",
            "\n* ",
            "\n> ",
            "```",
            "**",
            "__",
            "|",
            "1. "
        ]

        if text.hasPrefix("#")
            || text.hasPrefix("- ")
            || text.hasPrefix("* ")
            || text.hasPrefix("> ")
            || text.hasPrefix("1. ")
            || text.contains("```") {
            return true
        }

        return markers.contains { text.contains($0) }
    }

    static func looksLikeIncompleteMarkdown(_ text: String) -> Bool {
        let fencedCodeBlockCount = text.components(separatedBy: "```").count - 1
        if fencedCodeBlockCount % 2 == 1 {
            return true
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let danglingSuffixes = ["[", "](", "![", "`", "*", "_", "~"]
        if danglingSuffixes.contains(where: { trimmed.hasSuffix($0) }) {
            return true
        }

        let incompleteLinkPatterns = [
            #"\[[^\]]*$"#,
            #"\[[^\]]+\]\([^\)]*$"#,
            #"!\[[^\]]*$"#,
            #"!\[[^\]]+\]\([^\)]*$"#
        ]

        return incompleteLinkPatterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return false
            }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            return regex.firstMatch(in: trimmed, options: [], range: range) != nil
        }
    }
}

private enum WorkspaceStreamingMarkdownPlan: Equatable {
    case plainText(String)
    case markdown(String)
    case hybrid(markdownPrefix: String, plainTextSuffix: String)
}

private enum WorkspaceStreamingMarkdownBoundary {
    static func stablePrefixEnd(in text: String) -> String.Index? {
        if let danglingStart = danglingMarkdownStart(in: text) {
            return blockStart(in: text, before: danglingStart)
        }

        if let unmatchedFenceStart = unmatchedCodeFenceStart(in: text) {
            return blockStart(in: text, before: unmatchedFenceStart)
        }

        guard text.hasSuffix("\n") == false else {
            return nil
        }

        guard let separatorRange = text.range(of: "\n\n", options: .backwards) else {
            return nil
        }

        return separatorRange.upperBound
    }

    private static func blockStart(in text: String, before index: String.Index) -> String.Index {
        guard index > text.startIndex else {
            return text.startIndex
        }

        let prefix = text[..<index]
        if let separatorRange = prefix.range(of: "\n\n", options: .backwards) {
            return separatorRange.upperBound
        }
        return text.startIndex
    }

    private static func danglingMarkdownStart(in text: String) -> String.Index? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        let patterns = [
            #"\[[^\]]*$"#,
            #"\[[^\]]+\]\([^\)]*$"#,
            #"!\[[^\]]*$"#,
            #"!\[[^\]]+\]\([^\)]*$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = regex.firstMatch(in: trimmed, options: [], range: range),
               let matchRange = Range(match.range, in: trimmed) {
                return matchRange.lowerBound
            }
        }

        return nil
    }

    private static func unmatchedCodeFenceStart(in text: String) -> String.Index? {
        var searchStart = text.startIndex
        var openingFenceStart: String.Index?
        var insideFence = false

        while let range = text.range(of: "```", range: searchStart..<text.endIndex) {
            if insideFence == false {
                openingFenceStart = range.lowerBound
            }
            insideFence.toggle()
            searchStart = range.upperBound
        }

        return insideFence ? openingFenceStart : nil
    }
}

public struct WorkspaceMarkdownText: View {

    private let text: String
    private let isStreaming: Bool
    private let prefersMarkdown: Bool

    public init(
        _ text: String,
        isStreaming: Bool = false,
        prefersMarkdown: Bool = false
    ) {
        self.text = text
        self.isStreaming = isStreaming
        self.prefersMarkdown = prefersMarkdown
    }

    public var body: some View {
        let normalized = WorkspaceMarkdownSourceFormatter.normalized(text)
        switch renderPlan(for: normalized) {
        case let .plainText(content):
            Text(verbatim: content)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        case let .markdown(content):
            Markdown(WorkspaceMarkdownContentCache.shared.content(for: content))
                .markdownTheme(.basic)
                .markdownBlockStyle(\.heading1, body: compactMarkdownHeading)
                .markdownBlockStyle(\.heading2, body: compactMarkdownHeading)
                .markdownBlockStyle(\.heading3, body: compactMarkdownHeading)
                .markdownBlockStyle(\.heading4, body: compactMarkdownHeading)
                .markdownBlockStyle(\.heading5, body: compactMarkdownHeading)
                .markdownBlockStyle(\.heading6, body: compactMarkdownHeading)
                .fixedSize(horizontal: false, vertical: true)
        case let .hybrid(markdownPrefix, plainTextSuffix):
            VStack(alignment: .leading, spacing: 10) {
                Markdown(WorkspaceMarkdownContentCache.shared.content(for: markdownPrefix))
                    .markdownTheme(.basic)
                    .markdownBlockStyle(\.heading1, body: compactMarkdownHeading)
                    .markdownBlockStyle(\.heading2, body: compactMarkdownHeading)
                    .markdownBlockStyle(\.heading3, body: compactMarkdownHeading)
                    .markdownBlockStyle(\.heading4, body: compactMarkdownHeading)
                    .markdownBlockStyle(\.heading5, body: compactMarkdownHeading)
                    .markdownBlockStyle(\.heading6, body: compactMarkdownHeading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: plainTextSuffix)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func renderPlan(for normalized: String) -> WorkspaceStreamingMarkdownPlan {
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .plainText(normalized)
        }

        let prefersStructuredRendering = prefersMarkdown || WorkspaceMarkdownRenderMode.looksLikeMarkdown(trimmed)
        guard prefersStructuredRendering else {
            return .plainText(normalized)
        }

        guard isStreaming else {
            return .markdown(normalized)
        }

        guard let splitIndex = WorkspaceStreamingMarkdownBoundary.stablePrefixEnd(in: normalized) else {
            return .markdown(normalized)
        }

        let markdownPrefix = String(normalized[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let plainTextSuffix = String(normalized[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)

        if markdownPrefix.isEmpty {
            return .plainText(normalized)
        }

        if plainTextSuffix.isEmpty {
            return .markdown(normalized)
        }

        return .hybrid(markdownPrefix: markdownPrefix, plainTextSuffix: plainTextSuffix)
    }
}

@MainActor
private func compactMarkdownHeading(configuration: BlockConfiguration) -> some View {
    configuration.label
        .markdownMargin(top: .em(0.6), bottom: .em(0.35))
        .markdownTextStyle {
            FontWeight(.semibold)
            FontSize(.em(1))
        }
}

private enum WorkspaceMarkdownRenderLog {
    static func append(_ message: String) {
        guard ProcessInfo.processInfo.environment["HERMES_DESK_DEBUG_LOGS"] == "1" else {
            return
        }
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let directoryURL = supportURL.appending(path: "HermesDesk", directoryHint: .isDirectory)
        let fileURL = directoryURL.appending(path: "run-events-debug.log")
        let line = "[\(formatter.string(from: Date()))] \(message)\n"

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) == false {
                try Data(line.utf8).write(to: fileURL)
            } else if let handle = try? FileHandle(forWritingTo: fileURL) {
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            }
        } catch {
            return
        }
    }

    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private final class WorkspaceMarkdownContentBox {
    let content: MarkdownContent

    init(content: MarkdownContent) {
        self.content = content
    }
}

private final class WorkspaceStringBox {
    let value: String

    init(value: String) {
        self.value = value
    }
}

private final class WorkspaceStringTransformCache: @unchecked Sendable {
    static let normalized = WorkspaceStringTransformCache(countLimit: 64)
    static let preview = WorkspaceStringTransformCache(countLimit: 96)

    private let cache = NSCache<NSString, WorkspaceStringBox>()
    private let lock = NSLock()

    private init(countLimit: Int) {
        cache.countLimit = countLimit
    }

    func value(for text: String, transform: (String) -> String) -> String {
        let key = text as NSString
        if let cached = cache.object(forKey: key) {
            return cached.value
        }

        let transformed = transform(text)

        lock.lock()
        cache.setObject(WorkspaceStringBox(value: transformed), forKey: key)
        lock.unlock()

        return transformed
    }
}

private final class WorkspaceMarkdownContentCache: @unchecked Sendable {
    static let shared = WorkspaceMarkdownContentCache()

    private let cache = NSCache<NSString, WorkspaceMarkdownContentBox>()
    private let lock = NSLock()

    private init() {
        cache.countLimit = 64
    }

    func content(for text: String) -> MarkdownContent {
        let key = text as NSString
        if let cached = cache.object(forKey: key) {
            return cached.content
        }

        let start = ContinuousClock.now
        let content = MarkdownContent(text)
        let elapsed = start.duration(to: .now)

        lock.lock()
        cache.setObject(WorkspaceMarkdownContentBox(content: content), forKey: key)
        lock.unlock()

        if elapsed > .milliseconds(8) {
            WorkspaceMarkdownRenderLog.append(
                "markdown parse slow chars=\(text.count) ms=\(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)"
            )
        }

        return content
    }
}
