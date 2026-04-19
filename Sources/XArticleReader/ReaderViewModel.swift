import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ReaderViewModel {
    private static let wordHighlightingEnabledKey = "reader.wordHighlightingEnabled"

    var selectedArticle: Article?
    var selectedRange: NSRange?
    var selectedText: String = ""
    var activeParagraphIndex: Int?
    var activeParagraphRange: NSRange?
    var activeWordRange: NSRange?
    var isWordHighlightingEnabled: Bool = UserDefaults.standard.object(forKey: wordHighlightingEnabledKey) as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(isWordHighlightingEnabled, forKey: Self.wordHighlightingEnabledKey)
            if !isWordHighlightingEnabled {
                activeWordRange = nil
            }
        }
    }

    func selectArticle(_ article: Article?) {
        selectedArticle = article
        clearSelection()
        activeParagraphIndex = nil
        activeParagraphRange = nil
        activeWordRange = nil
    }

    func updateSelection(range: NSRange, in text: String) {
        guard range.location != NSNotFound, range.length > 0 else {
            clearSelection()
            return
        }
        selectedRange = range
        selectedText = ArticleTextProcessor.excerpt(in: text, range: range)
    }

    func setSelection(range: NSRange, excerpt: String) {
        guard range.location != NSNotFound, range.length > 0 else {
            clearSelection()
            return
        }
        selectedRange = range
        selectedText = excerpt
    }

    func syncPlayback(paragraphIndex: Int?, paragraphRange: NSRange?, wordRange: NSRange?) {
        activeParagraphIndex = paragraphIndex
        activeParagraphRange = paragraphRange
        activeWordRange = isWordHighlightingEnabled ? wordRange : nil
    }

    func setWordHighlightingEnabled(_ enabled: Bool, paragraphIndex: Int?, paragraphRange: NSRange?, wordRange: NSRange?) {
        isWordHighlightingEnabled = enabled
        syncPlayback(paragraphIndex: paragraphIndex, paragraphRange: paragraphRange, wordRange: wordRange)
    }

    func addHighlight(using modelContext: ModelContext) {
        guard
            let article = selectedArticle,
            let selectedRange,
            selectedRange.length > 0
        else {
            return
        }

        let clippedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clippedText.isEmpty else { return }

        let highlight = Highlight(
            selectedText: clippedText,
            startOffset: selectedRange.location,
            endOffset: selectedRange.location + selectedRange.length,
            article: article
        )
        article.highlights.append(highlight)
        article.updatedAt = .now
        modelContext.insert(highlight)
        clearSelection()
    }

    func clearSelection() {
        selectedRange = nil
        selectedText = ""
    }
}
