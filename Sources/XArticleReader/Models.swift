import Foundation
import SwiftData

@Model
final class Article {
    @Attribute(.unique) var id: UUID
    var title: String
    var sourceLabel: String
    @Attribute(.externalStorage) var bodyText: String
    var createdAt: Date
    var updatedAt: Date
    var lastPlayedAt: Date?
    var estimatedReadingMinutes: Int
    var lastPlaybackOffset: Double
    var lastReadPosition: Int
    var lastBackendIdentifier: String?
    var lastVoiceIdentifier: String
    var lastSpeed: Double
    var isFinished: Bool

    @Relationship(deleteRule: .cascade, inverse: \Highlight.article)
    var highlights: [Highlight]

    init(
        id: UUID = UUID(),
        title: String,
        sourceLabel: String = "",
        bodyText: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastPlayedAt: Date? = nil,
        estimatedReadingMinutes: Int,
        lastPlaybackOffset: Double = 0,
        lastReadPosition: Int = 0,
        lastBackendIdentifier: String? = "kokoro",
        lastVoiceIdentifier: String = "",
        lastSpeed: Double = 1.0,
        isFinished: Bool = false,
        highlights: [Highlight] = []
    ) {
        self.id = id
        self.title = title
        self.sourceLabel = sourceLabel
        self.bodyText = bodyText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastPlayedAt = lastPlayedAt
        self.estimatedReadingMinutes = estimatedReadingMinutes
        self.lastPlaybackOffset = lastPlaybackOffset
        self.lastReadPosition = lastReadPosition
        self.lastBackendIdentifier = lastBackendIdentifier
        self.lastVoiceIdentifier = lastVoiceIdentifier
        self.lastSpeed = lastSpeed
        self.isFinished = isFinished
        self.highlights = highlights
    }
}

@Model
final class Highlight {
    @Attribute(.unique) var id: UUID
    var selectedText: String
    var startOffset: Int
    var endOffset: Int
    var colorStyle: String
    var createdAt: Date
    var article: Article?

    init(
        id: UUID = UUID(),
        selectedText: String,
        startOffset: Int,
        endOffset: Int,
        colorStyle: String = "sun",
        createdAt: Date = .now,
        article: Article? = nil
    ) {
        self.id = id
        self.selectedText = selectedText
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.colorStyle = colorStyle
        self.createdAt = createdAt
        self.article = article
    }
}

@Model
final class ArticleComment {
    @Attribute(.unique) var id: UUID
    var articleID: UUID
    var selectedText: String
    var noteBody: String
    var startOffset: Int
    var endOffset: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        articleID: UUID,
        selectedText: String,
        noteBody: String,
        startOffset: Int,
        endOffset: Int,
        createdAt: Date = .now
    ) {
        self.id = id
        self.articleID = articleID
        self.selectedText = selectedText
        self.noteBody = noteBody
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.createdAt = createdAt
    }
}

extension Article {
    var readingProgress: Double {
        let totalLength = max(1, bodyText.utf16.count)
        return min(max(Double(lastReadPosition) / Double(totalLength), 0), 1)
    }

    var displaySource: String {
        sourceLabel.isEmpty ? "Pasted article" : sourceLabel
    }
}
