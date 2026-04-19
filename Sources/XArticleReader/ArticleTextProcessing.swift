import Foundation

struct NormalizedArticleText {
    let title: String
    let sourceLabel: String
    let bodyText: String
    let estimatedReadingMinutes: Int
}

enum ParagraphRole: Equatable {
    case heading
    case body
    case listItem
    case quote
}

struct ParagraphSegment: Identifiable, Equatable {
    let id: Int
    let index: Int
    let text: String
    let range: NSRange
    let startTime: TimeInterval
    let estimatedDuration: TimeInterval
    let sectionIndex: Int
    let role: ParagraphRole
}

struct TimestampMarker: Identifiable, Equatable {
    let id: Int
    let label: String
    let textOffset: Int
    let paragraphRange: NSRange
    let paragraphIndex: Int
    let stackIndex: Int
}

enum ArticleTextProcessor {
    static let sectionInterval: TimeInterval = 60
    private static let canonicalCharactersPerSecond = 14.0

    static func normalize(title: String, sourceLabel: String, bodyText: String) -> NormalizedArticleText {
        let cleanedTitle = collapsed(title).trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedSource = collapsed(sourceLabel).trimmingCharacters(in: .whitespacesAndNewlines)

        let paragraphs = splitIntoParagraphs(bodyText)
        let normalizedBody = paragraphs.joined(separator: "\n\n")
        let fallbackTitle = paragraphs.first.map(shortTitle(from:)) ?? "Untitled Article"

        return NormalizedArticleText(
            title: cleanedTitle.isEmpty ? fallbackTitle : cleanedTitle,
            sourceLabel: cleanedSource,
            bodyText: normalizedBody,
            estimatedReadingMinutes: estimatedReadingMinutes(for: normalizedBody)
        )
    }

    static func paragraphSegments(for bodyText: String, speed: Double) -> [ParagraphSegment] {
        let paragraphs = bodyText.components(separatedBy: "\n\n")
        var offset = 0
        var elapsed: TimeInterval = 0
        return paragraphs.enumerated().map { index, paragraph in
            let length = paragraph.utf16.count
            let range = NSRange(location: offset, length: length)
            let duration = estimatedDuration(forUTF16Length: length, speed: speed)
            offset += length + 2
            defer {
                elapsed += duration
            }
            return ParagraphSegment(
                id: index,
                index: index,
                text: paragraph,
                range: range,
                startTime: elapsed,
                estimatedDuration: duration,
                sectionIndex: Int(elapsed / sectionInterval),
                role: paragraphRole(for: paragraph)
            )
        }
    }

    static func timestampMarkers(
        for bodyText: String,
        speed: Double,
        interval: TimeInterval = sectionInterval
    ) -> [TimestampMarker] {
        guard interval > 0 else { return [] }

        let segments = paragraphSegments(for: bodyText, speed: speed)
        guard let lastSegment = segments.last else { return [] }

        let totalDuration = totalEstimatedPlaybackDuration(for: bodyText, speed: speed)
        let sectionCount = max(Int(ceil(totalDuration / interval)), 1)
        var stacks: [Int: Int] = [:]
        var markers: [TimestampMarker] = []

        for section in 0..<sectionCount {
            let boundary = TimeInterval(section) * interval
            let offset = estimatedTextOffset(for: boundary, bodyText: bodyText, speed: speed)
            let segment = segments.first(where: { NSLocationInRange(offset, $0.range) || offset <= NSMaxRange($0.range) }) ?? lastSegment
            let stackKey = max(0, min(offset, max(bodyText.utf16.count - 1, 0)))
            let stackIndex = stacks[stackKey, default: 0]
            stacks[stackKey] = stackIndex + 1
            markers.append(
                TimestampMarker(
                    id: section,
                    label: timestampLabel(for: boundary),
                    textOffset: offset,
                    paragraphRange: segment.range,
                    paragraphIndex: segment.index,
                    stackIndex: stackIndex
                )
            )
        }

        return markers
    }

    static func paragraphIndex(for offset: Int, in bodyText: String, speed: Double) -> Int {
        let segments = paragraphSegments(for: bodyText, speed: speed)
        for segment in segments {
            if NSLocationInRange(offset, segment.range) || offset <= segment.range.location {
                return segment.index
            }
        }
        return max(segments.count - 1, 0)
    }

    static func estimatedOffsetDelta(for seconds: TimeInterval, speed: Double) -> Int {
        Int((seconds * charactersPerSecond(for: speed)).rounded())
    }

    static func estimatedPlaybackOffset(for position: Int, bodyText: String, speed: Double) -> TimeInterval {
        guard !bodyText.isEmpty else { return 0 }
        let clamped = max(0, min(position, bodyText.utf16.count))
        return Double(clamped) / charactersPerSecond(for: speed)
    }

    static func estimatedTextOffset(for time: TimeInterval, bodyText: String, speed: Double) -> Int {
        let rawOffset = Int((time * charactersPerSecond(for: speed)).rounded())
        return max(0, min(rawOffset, bodyText.utf16.count))
    }

    static func totalEstimatedPlaybackDuration(for bodyText: String, speed: Double) -> TimeInterval {
        estimatedPlaybackOffset(for: bodyText.utf16.count, bodyText: bodyText, speed: speed)
    }

    static func timestampLabel(for time: TimeInterval) -> String {
        let total = max(Int(time.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func timestampLabel(forTextOffset offset: Int, bodyText: String, speed: Double) -> String {
        timestampLabel(for: estimatedPlaybackOffset(for: offset, bodyText: bodyText, speed: speed))
    }

    static func excerpt(in bodyText: String, range: NSRange) -> String {
        let nsText = bodyText as NSString
        guard range.location != NSNotFound, range.location >= 0, NSMaxRange(range) <= nsText.length else {
            return ""
        }
        return nsText.substring(with: range)
    }

    private static func splitIntoParagraphs(_ rawText: String) -> [String] {
        let rawLines = rawText.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var paragraphs: [String] = []
        var current: [String] = []

        for rawLine in rawLines {
            let line = collapsed(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                if !current.isEmpty {
                    paragraphs.append(current.joined(separator: " "))
                    current.removeAll()
                }
            } else if isStandaloneLine(line) {
                if !current.isEmpty {
                    paragraphs.append(current.joined(separator: " "))
                    current.removeAll()
                }
                paragraphs.append(line)
            } else {
                current.append(line)
            }
        }

        if !current.isEmpty {
            paragraphs.append(current.joined(separator: " "))
        }

        return paragraphs.filter { !$0.isEmpty }
    }

    private static func shortTitle(from paragraph: String) -> String {
        let capped = String(paragraph.prefix(72)).trimmingCharacters(in: .whitespacesAndNewlines)
        return capped.isEmpty ? "Untitled Article" : capped
    }

    private static func estimatedReadingMinutes(for bodyText: String) -> Int {
        let words = bodyText.split(whereSeparator: \.isWhitespace).count
        return max(1, Int(ceil(Double(words) / 180.0)))
    }

    private static func paragraphRole(for paragraph: String) -> ParagraphRole {
        if isListLike(paragraph) {
            return .listItem
        }

        if paragraph.hasPrefix(">") {
            return .quote
        }

        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeHeading(trimmed) {
            return .heading
        }

        return .body
    }

    static func estimatedDuration(forUTF16Length length: Int, speed: Double) -> TimeInterval {
        Double(length) / charactersPerSecond(for: speed)
    }

    private static func charactersPerSecond(for speed: Double) -> Double {
        // Reader timestamps should represent a stable article timeline, not shift around
        // when playback speed or seeking changes.
        canonicalCharactersPerSecond
    }

    private static func collapsed(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func isStandaloneLine(_ line: String) -> Bool {
        isListLike(line) || line.hasPrefix(">") || isAllCapsHeading(line)
    }

    private static func isListLike(_ line: String) -> Bool {
        let patterns = [
            #"^[-*•]\s+"#,
            #"^\d+[.)]\s+"#,
        ]
        return patterns.contains { pattern in
            line.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func looksLikeHeading(_ text: String) -> Bool {
        guard text.count <= 84, text.split(whereSeparator: \.isWhitespace).count <= 10 else {
            return false
        }

        return isAllCapsHeading(text) || !containsSentenceEndingPunctuation(text)
    }

    private static func isAllCapsHeading(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter(CharacterSet.letters.contains)
        guard !letters.isEmpty else { return false }
        return letters.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
    }

    private static func containsSentenceEndingPunctuation(_ text: String) -> Bool {
        text.contains(".") || text.contains("!") || text.contains("?")
    }
}
