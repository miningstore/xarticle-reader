import AppKit
import SwiftUI

struct ArticleReaderTextView: NSViewRepresentable {
    let text: String
    let paragraphSegments: [ParagraphSegment]
    let timestampMarkers: [TimestampMarker]
    let highlights: [Highlight]
    let comments: [ArticleComment]
    let activeParagraphRange: NSRange?
    let activeWordRange: NSRange?
    let shouldFollowPlayback: Bool
    let followPlaybackRequestID: Int
    let onSelectionChange: (NSRange, String) -> Void
    let onSeekRequest: (Int) -> Void
    let onCommentRequest: (NSRange, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSelectionChange: onSelectionChange,
            onSeekRequest: onSeekRequest,
            onCommentRequest: onCommentRequest
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ReaderScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = ReaderTheme.paperNSColor
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 118, right: 0)
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 118, right: 6)
        scrollView.onUserScroll = {
            context.coordinator.suspendFollowUntil = Date().addingTimeInterval(8)
        }

        let textView = ReaderTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = ReaderTheme.paperNSColor
        textView.textColor = ReaderTheme.primaryTextNSColor
        textView.textContainerInset = NSSize(width: 82, height: 40)
        textView.textContainer?.lineFragmentPadding = 12
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.delegate = context.coordinator
        textView.allowsUndo = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.onSeekRequest = { location in
            context.coordinator.onSeekRequest(location)
        }
        textView.onCommentRequest = { range, excerpt in
            context.coordinator.onCommentRequest(range, excerpt)
        }

        scrollView.documentView = textView
        context.coordinator.lastVisibleRangeLocation = nil
        updateTextView(textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ReaderTextView else { return }
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onSeekRequest = onSeekRequest
        context.coordinator.onCommentRequest = onCommentRequest
        let followWasRequested = context.coordinator.lastFollowPlaybackRequestID != followPlaybackRequestID
        if followWasRequested {
            context.coordinator.lastFollowPlaybackRequestID = followPlaybackRequestID
            context.coordinator.suspendFollowUntil = .distantPast
        }
        context.coordinator.isApplyingViewUpdate = true
        updateTextView(textView, coordinator: context.coordinator)
        context.coordinator.isApplyingViewUpdate = false

        let followTargetRange = activeWordRange ?? activeParagraphRange
        guard
            shouldFollowPlayback,
            let followTargetRange,
            followTargetRange.location != context.coordinator.lastVisibleRangeLocation,
            (followWasRequested || Date() >= context.coordinator.suspendFollowUntil)
        else {
            return
        }

        context.coordinator.lastVisibleRangeLocation = followTargetRange.location
        textView.scrollRangeToVisible(followTargetRange)
    }

    private func updateTextView(_ textView: ReaderTextView, coordinator: Coordinator) {
        textView.backgroundColor = ReaderTheme.paperNSColor
        textView.textColor = ReaderTheme.primaryTextNSColor
        textView.timestampMarkers = timestampMarkers
        textView.sourceText = text

        let baseRenderKey = makeBaseRenderKey(activeParagraphRange: activeParagraphRange)
        if coordinator.lastBaseRenderKey != baseRenderKey || textView.textStorage?.length != text.utf16.count {
            let selectedRange = textView.selectedRange()
            let attributed = buildAttributedText(activeParagraphRange: activeParagraphRange)
            textView.textStorage?.setAttributedString(attributed)
            if selectedRange.location != NSNotFound, NSMaxRange(selectedRange) <= attributed.length {
                textView.setSelectedRange(selectedRange)
            }
            coordinator.lastBaseRenderKey = baseRenderKey
            coordinator.lastAppliedWordRange = nil
            coordinator.lastAppliedParagraphRange = activeParagraphRange
        }

        applyActiveWordHighlight(
            in: textView,
            previousRange: coordinator.lastAppliedWordRange,
            newRange: activeWordRange,
            activeParagraphRange: activeParagraphRange
        )
        coordinator.lastAppliedWordRange = activeWordRange
        coordinator.lastAppliedParagraphRange = activeParagraphRange
    }

    private func buildAttributedText(activeParagraphRange: NSRange?) -> NSMutableAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: bodyFont(),
                .foregroundColor: ReaderTheme.primaryTextNSColor,
                .paragraphStyle: defaultParagraphStyle(),
            ]
        )

        for segment in paragraphSegments {
            let isSectionStart = timestampMarkers.contains(where: { $0.paragraphIndex == segment.index })
            let paragraphStyle = paragraphStyle(for: segment.role, isSectionStart: isSectionStart)
            attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: segment.range)
            attributed.addAttribute(.font, value: font(for: segment.role), range: segment.range)
            attributed.addAttribute(.foregroundColor, value: color(for: segment.role), range: segment.range)
        }

        for highlight in highlights {
            let range = NSRange(location: highlight.startOffset, length: max(0, highlight.endOffset - highlight.startOffset))
            if range.location != NSNotFound, NSMaxRange(range) <= attributed.length {
                attributed.addAttribute(.backgroundColor, value: ReaderTheme.savedHighlightNSColor, range: range)
            }
        }

        for comment in comments {
            let range = NSRange(location: comment.startOffset, length: max(0, comment.endOffset - comment.startOffset))
            if range.location != NSNotFound, NSMaxRange(range) <= attributed.length {
                attributed.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: ReaderTheme.commentUnderlineNSColor,
                ], range: range)
            }
        }

        if let activeParagraphRange, activeParagraphRange.location != NSNotFound, NSMaxRange(activeParagraphRange) <= attributed.length {
            attributed.addAttribute(.backgroundColor, value: ReaderTheme.activeParagraphNSColor, range: activeParagraphRange)
        }

        return attributed
    }

    private func applyActiveWordHighlight(
        in textView: ReaderTextView,
        previousRange: NSRange?,
        newRange: NSRange?,
        activeParagraphRange: NSRange?
    ) {
        guard let textStorage = textView.textStorage else { return }

        if let previousRange, previousRange.location != NSNotFound, NSMaxRange(previousRange) <= textStorage.length {
            restoreBackground(in: textStorage, range: previousRange, activeParagraphRange: activeParagraphRange)
        }

        guard let newRange, newRange.location != NSNotFound, NSMaxRange(newRange) <= textStorage.length else {
            return
        }

        textStorage.addAttribute(.backgroundColor, value: ReaderTheme.activeWordNSColor, range: newRange)
    }

    private func restoreBackground(in textStorage: NSTextStorage, range: NSRange, activeParagraphRange: NSRange?) {
        guard range.length > 0 else { return }

        if
            let activeParagraphRange,
            activeParagraphRange.location != NSNotFound,
            let intersection = intersection(range, activeParagraphRange)
        {
            if intersection.location > range.location {
                textStorage.removeAttribute(.backgroundColor, range: NSRange(location: range.location, length: intersection.location - range.location))
            }
            textStorage.addAttribute(.backgroundColor, value: ReaderTheme.activeParagraphNSColor, range: intersection)
            let intersectionEnd = NSMaxRange(intersection)
            if intersectionEnd < NSMaxRange(range) {
                textStorage.removeAttribute(.backgroundColor, range: NSRange(location: intersectionEnd, length: NSMaxRange(range) - intersectionEnd))
            }
        } else {
            textStorage.removeAttribute(.backgroundColor, range: range)
        }
    }

    private func makeBaseRenderKey(activeParagraphRange: NSRange?) -> String {
        let highlightsKey = highlights
            .map { "\($0.startOffset)-\($0.endOffset)" }
            .joined(separator: "|")
        let commentsKey = comments
            .map { "\($0.startOffset)-\($0.endOffset)-\($0.createdAt.timeIntervalSince1970)" }
            .joined(separator: "|")
        let paragraphKey = activeParagraphRange.map { "\($0.location):\($0.length)" } ?? "nil"
        return "\(text.count)#\(paragraphSegments.count)#\(timestampMarkers.count)#\(highlightsKey)#\(commentsKey)#\(paragraphKey)"
    }

    private func intersection(_ lhs: NSRange, _ rhs: NSRange) -> NSRange? {
        let start = max(lhs.location, rhs.location)
        let end = min(NSMaxRange(lhs), NSMaxRange(rhs))
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private func bodyFont() -> NSFont {
        NSFont(name: "Palatino", size: 20) ?? NSFont.systemFont(ofSize: 20)
    }

    private func font(for role: ParagraphRole) -> NSFont {
        switch role {
        case .heading:
            return NSFont(name: "Palatino-Bold", size: 24) ?? NSFont.boldSystemFont(ofSize: 24)
        case .quote:
            return NSFont(name: "Palatino-Italic", size: 20) ?? NSFont.systemFont(ofSize: 20)
        case .listItem, .body:
            return bodyFont()
        }
    }

    private func color(for role: ParagraphRole) -> NSColor {
        switch role {
        case .heading:
            return ReaderTheme.headingTextNSColor
        case .quote:
            return ReaderTheme.secondaryTextNSColor
        case .listItem, .body:
            return ReaderTheme.primaryTextNSColor
        }
    }

    private func defaultParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 9
        style.paragraphSpacing = 24
        style.paragraphSpacingBefore = 0
        style.firstLineHeadIndent = 28
        style.headIndent = 8
        style.tailIndent = -8
        return style
    }

    private func paragraphStyle(for role: ParagraphRole, isSectionStart: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        switch role {
        case .heading:
            style.lineSpacing = 6
            style.paragraphSpacing = 16
            style.paragraphSpacingBefore = isSectionStart ? 36 : 24
            style.firstLineHeadIndent = 20
            style.headIndent = 20
        case .quote:
            style.lineSpacing = 10
            style.paragraphSpacing = 24
            style.paragraphSpacingBefore = isSectionStart ? 22 : 8
            style.firstLineHeadIndent = 44
            style.headIndent = 44
        case .listItem:
            style.lineSpacing = 9
            style.paragraphSpacing = 12
            style.paragraphSpacingBefore = isSectionStart ? 18 : 0
            style.firstLineHeadIndent = 34
            style.headIndent = 34
        case .body:
            style.lineSpacing = 9
            style.paragraphSpacing = 24
            style.paragraphSpacingBefore = isSectionStart ? 28 : 0
            style.firstLineHeadIndent = isSectionStart ? 38 : 28
            style.headIndent = isSectionStart ? 16 : 8
        }
        style.tailIndent = -8
        return style
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectionChange: (NSRange, String) -> Void
        var onSeekRequest: (Int) -> Void
        var onCommentRequest: (NSRange, String) -> Void
        var isApplyingViewUpdate = false
        var lastVisibleRangeLocation: Int?
        var lastFollowPlaybackRequestID: Int = 0
        var suspendFollowUntil = Date.distantPast
        var lastBaseRenderKey: String?
        var lastAppliedParagraphRange: NSRange?
        var lastAppliedWordRange: NSRange?

        init(
            onSelectionChange: @escaping (NSRange, String) -> Void,
            onSeekRequest: @escaping (Int) -> Void,
            onCommentRequest: @escaping (NSRange, String) -> Void
        ) {
            self.onSelectionChange = onSelectionChange
            self.onSeekRequest = onSeekRequest
            self.onCommentRequest = onCommentRequest
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingViewUpdate, let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let excerpt = ArticleTextProcessor.excerpt(in: textView.string, range: range)
            onSelectionChange(range, excerpt)
        }
    }
}

final class ReaderTextView: NSTextView {
    var timestampMarkers: [TimestampMarker] = [] {
        didSet {
            needsDisplay = true
        }
    }
    var sourceText: String = ""
    var onSeekRequest: ((Int) -> Void)?
    var onCommentRequest: ((NSRange, String) -> Void)?

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let range = selectedRange()
        guard event.clickCount == 1, range.location != NSNotFound, range.length == 0 else { return }
        onSeekRequest?(range.location)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        let insertionIndex = characterIndexForInsertion(at: location)
        let currentSelection = selectedRange()
        let clickedInsideSelection =
            currentSelection.location != NSNotFound &&
            currentSelection.length > 0 &&
            NSLocationInRange(insertionIndex, currentSelection)

        if !clickedInsideSelection {
            setSelectedRange(NSRange(location: insertionIndex, length: 0))
        }

        let menu = super.menu(for: event) ?? NSMenu()
        let range = selectedRange()
        if range.location != NSNotFound, range.length > 0 {
            if menu.items.last?.isSeparatorItem == false {
                menu.addItem(.separator())
            }
            let item = NSMenuItem(title: "Add Note", action: #selector(addCommentFromMenu), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func addCommentFromMenu() {
        let range = selectedRange()
        guard range.location != NSNotFound, range.length > 0 else { return }
        let excerpt = ArticleTextProcessor.excerpt(in: sourceText, range: range)
        onCommentRequest?(range, excerpt)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawTimestampMarkers()
    }

    private func drawTimestampMarkers() {
        guard
            let layoutManager,
            !timestampMarkers.isEmpty
        else {
            return
        }

        let origin = textContainerOrigin
        let chipFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let textLength = textStorage?.length ?? 0
        let gutterWidth = max(textContainerInset.width - 12, 64)

        for marker in timestampMarkers {
            let clampedOffset = max(0, min(marker.textOffset, max(textLength - 1, 0)))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedOffset)
            var lineRange = NSRange(location: NSNotFound, length: 0)
            let lineRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineRange,
                withoutAdditionalLayout: true
            )
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: chipFont,
                .foregroundColor: ReaderTheme.timestampTextNSColor,
            ]
            let labelSize = marker.label.size(withAttributes: labelAttributes)
            let chipWidth = min(max(58, ceil(labelSize.width) + 20), gutterWidth)
            let chipRect = NSRect(
                x: max(8, gutterWidth - chipWidth),
                y: origin.y + lineRect.minY - 2 + CGFloat(marker.stackIndex * 24),
                width: chipWidth,
                height: 22
            )

            let chipPath = NSBezierPath(roundedRect: chipRect, xRadius: 11, yRadius: 11)
            ReaderTheme.timestampChipNSColor.setFill()
            chipPath.fill()

            let label = NSMutableAttributedString(
                string: marker.label,
                attributes: labelAttributes
            )

            let textRect = NSRect(
                x: chipRect.minX + max(8, floor((chipRect.width - labelSize.width) / 2)),
                y: chipRect.minY + 4,
                width: max(labelSize.width, chipRect.width - 12),
                height: chipRect.height - 6
            )
            label.draw(in: textRect)
        }
    }
}

final class ReaderScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onUserScroll?()
        super.scrollWheel(with: event)
    }
}
