import SwiftUI
import SwiftData

private enum AnnotationTab: String, CaseIterable, Identifiable {
    case highlights
    case notes

    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SpeechPlaybackService.self) private var speechService
    @Environment(ReaderViewModel.self) private var readerViewModel

    @Query(sort: \Article.createdAt, order: .reverse) private var articles: [Article]

    @State private var selectedArticleID: UUID?
    @State private var showingNewArticleSheet = false

    var body: some View {
        ZStack {
            NavigationSplitView {
                sidebar
            } detail: {
                detailPane
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewArticleSheet = true
                    } label: {
                        Label("New Article", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewArticleSheet) {
                NewArticleSheet()
            }
            .safeAreaInset(edge: .bottom) {
                if let article = selectedArticle {
                    PlayerBar(article: article)
                        .environment(speechService)
                        .environment(readerViewModel)
                        .background(.regularMaterial)
                        .overlay(alignment: .top) {
                            Divider()
                        }
                }
            }
            .disabled(speechService.shouldPresentProcessingOverlay)
            .blur(radius: speechService.shouldPresentProcessingOverlay ? 2 : 0)
            .onAppear {
                selectInitialArticleIfNeeded()
            }
            .onChange(of: articles.count) { _, _ in
                selectInitialArticleIfNeeded()
            }
            .onChange(of: selectedArticleID) { _, _ in
                readerViewModel.selectArticle(selectedArticle)
                if let article = selectedArticle {
                    speechService.configure(for: article)
                    syncReaderPlaybackState()
                }
            }
            .onChange(of: speechService.currentParagraphIndex) { _, _ in
                syncReaderPlaybackState()
            }
            .onChange(of: speechService.currentWordRange) { _, _ in
                syncReaderPlaybackState()
            }

            if speechService.shouldPresentProcessingOverlay {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()

                ProcessingOverlayCard()
                    .environment(speechService)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
            }
        }
    }

    private var selectedArticle: Article? {
        guard let selectedArticleID else { return articles.first }
        return articles.first(where: { $0.id == selectedArticleID })
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                    Text("\(articles.count) saved articles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            List(selection: $selectedArticleID) {
                ForEach(articles) { article in
                    ArticleRow(article: article, isSelected: article.id == selectedArticleID)
                        .tag(article.id)
                        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 310)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let article = selectedArticle {
            ReaderDetailView(article: article)
        } else {
            ContentUnavailableView(
                "No Articles Yet",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Paste a long-form article to start building your local reading library.")
            )
        }
    }

    private func selectInitialArticleIfNeeded() {
        if selectedArticleID == nil {
            selectedArticleID = articles.first?.id
        } else if selectedArticle == nil {
            selectedArticleID = articles.first?.id
        }
        readerViewModel.selectArticle(selectedArticle)
    }

    private func syncReaderPlaybackState() {
        readerViewModel.syncPlayback(
            paragraphIndex: speechService.currentParagraphIndex,
            paragraphRange: speechService.currentParagraphRange,
            wordRange: speechService.currentWordRange
        )
    }
}

private struct ProcessingOverlayCard: View {
    @Environment(SpeechPlaybackService.self) private var speechService

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)

                VStack(alignment: .leading, spacing: 4) {
                    Text(speechService.processingOverlayTitle)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                    Text(speechService.processingOverlayMessage)
                        .font(.subheadline)
                        .foregroundStyle(ReaderTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let progress = speechService.processingOverlayProgress {
                ProgressView(value: progress)
                    .tint(.accentColor)
            }

            if let eta = speechService.processingOverlayETA {
                Text(eta)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ReaderTheme.secondaryText)
            }

            Text("This section is being prepared on your Mac. Once it finishes, the generated audio is saved locally and reused so it does not need to be generated again.")
                .font(.footnote)
                .foregroundStyle(ReaderTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ReaderTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 28, x: 0, y: 14)
    }
}

private struct ArticleRow: View {
    let article: Article
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(article.displaySource)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if article.isFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            ProgressView(value: article.readingProgress)
                .tint(.accentColor)

            HStack {
                Text(article.createdAt.formatted(date: .abbreviated, time: .omitted))
                Spacer()
                Text(article.lastPlayedAt.map { "Played \($0.formatted(date: .omitted, time: .shortened))" } ?? "Unread")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 1)
        )
    }
}

private struct ReaderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SpeechPlaybackService.self) private var speechService
    @Environment(ReaderViewModel.self) private var readerViewModel

    @Query(sort: \ArticleComment.createdAt, order: .reverse) private var comments: [ArticleComment]

    let article: Article
    @State private var showingCommentSheet = false
    @State private var showingAnnotationSheet = false
    @State private var showingModelManager = false
    @State private var commentDraft = ""
    @State private var annotationTab: AnnotationTab = .highlights

    private var paragraphSegments: [ParagraphSegment] {
        ArticleTextProcessor.paragraphSegments(for: article.bodyText, speed: speechService.speed)
    }

    private var timestampMarkers: [TimestampMarker] {
        speechService.timestampMarkers(for: article)
    }

    private var articleComments: [ArticleComment] {
        comments.filter { $0.articleID == article.id }.sorted { $0.startOffset < $1.startOffset }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ArticleReaderTextView(
                text: article.bodyText,
                paragraphSegments: paragraphSegments,
                timestampMarkers: timestampMarkers,
                highlights: article.highlights.sorted { $0.startOffset < $1.startOffset },
                comments: articleComments,
                activeParagraphRange: readerViewModel.activeParagraphRange,
                activeWordRange: readerViewModel.activeWordRange,
                shouldFollowPlayback: speechService.isPlaying || speechService.isStartingPlayback,
                followPlaybackRequestID: speechService.followPlaybackRequestID
            ) { range, excerpt in
                readerViewModel.updateSelection(range: range, in: article.bodyText)
                if excerpt.isEmpty {
                    readerViewModel.clearSelection()
                }
            } onSeekRequest: { offset in
                speechService.seek(toTextOffset: offset, in: article)
            } onCommentRequest: { range, excerpt in
                readerViewModel.setSelection(range: range, excerpt: excerpt)
                commentDraft = ""
                showingCommentSheet = true
            }
            .padding(.horizontal, 42)
            .padding(.bottom, 18)
        }
        .background(
            LinearGradient(
                colors: [ReaderTheme.paper, ReaderTheme.pageGlow],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear {
            readerViewModel.selectArticle(article)
            speechService.configure(for: article)
            readerViewModel.syncPlayback(
                paragraphIndex: speechService.currentParagraphIndex,
                paragraphRange: speechService.currentParagraphRange,
                wordRange: speechService.currentWordRange
            )
        }
        .sheet(isPresented: $showingCommentSheet) {
            CommentComposerSheet(
                article: article,
                selectedText: readerViewModel.selectedText,
                draft: $commentDraft,
                onCancel: {
                    showingCommentSheet = false
                },
                onSave: saveComment
            )
        }
        .sheet(isPresented: $showingAnnotationSheet) {
            AnnotationReviewSheet(
                article: article,
                highlights: article.highlights.sorted { $0.startOffset < $1.startOffset },
                comments: articleComments,
                initialTab: annotationTab,
                timestampLabelForOffset: { speechService.timestampLabel(forTextOffset: $0, in: article) },
                onJump: { offset in
                    speechService.seek(toTextOffset: offset, in: article)
                    showingAnnotationSheet = false
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(article.title)
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 14) {
                        Label(article.displaySource, systemImage: "link")
                        Label("\(article.estimatedReadingMinutes) min read", systemImage: "clock")
                        Label("\(article.highlights.count) highlights", systemImage: "highlighter")
                        Label("\(articleComments.count) notes", systemImage: "text.bubble")
                    }
                    .font(.subheadline)
                    .foregroundStyle(ReaderTheme.secondaryText)
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 10) {
                    Label(speechService.selectedBackendID.displayName, systemImage: "waveform.and.mic")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(ReaderTheme.panelSurface))

                    Button(showingModelManager ? "Hide Voice Setup" : "Manage Voices") {
                        showingModelManager.toggle()
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    Button {
                        speechService.togglePlayback(for: article)
                    } label: {
                        Label(playbackButtonTitle, systemImage: playbackButtonSymbol)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        speechService.seek(by: -30, in: article)
                    } label: {
                        Label("Back 30s", systemImage: "gobackward.30")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        speechService.seek(by: 30, in: article)
                    } label: {
                        Label("Forward 30s", systemImage: "goforward.30")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ReaderTheme.panelSurface))

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    Button {
                        annotationTab = .highlights
                        showingAnnotationSheet = true
                    } label: {
                        Label("Highlights", systemImage: "sparkles.rectangle.stack")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        annotationTab = .notes
                        showingAnnotationSheet = true
                    } label: {
                        Label("Notes", systemImage: "text.bubble")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !readerViewModel.selectedText.isEmpty {
                SelectionActionBar(
                    selectedText: readerViewModel.selectedText,
                    onHighlight: { readerViewModel.addHighlight(using: modelContext) },
                    onComment: beginCommentFromCurrentSelection
                )
            }

            if shouldShowBackendStatus {
                Text(speechService.backendStatusMessage)
                    .font(.caption)
                    .foregroundStyle(ReaderTheme.secondaryText)
                    .lineLimit(2)
            }

            if shouldShowModelStrip {
                ModelStatusStrip(article: article)
            }
        }
        .padding(.horizontal, 42)
        .padding(.top, 28)
        .padding(.bottom, 24)
    }

    private var playbackButtonTitle: String {
        if speechService.isStartingPlayback {
            return "Stop"
        }
        return speechService.isPlaying ? "Pause" : "Play"
    }

    private var playbackButtonSymbol: String {
        if speechService.isStartingPlayback {
            return "stop.fill"
        }
        return speechService.isPlaying ? "pause.fill" : "play.fill"
    }

    private var shouldShowBackendStatus: Bool {
        let lowered = speechService.backendStatusMessage.lowercased()
        return lowered.contains("failed") || lowered.contains("error")
    }

    private var shouldShowModelStrip: Bool {
        showingModelManager || !(speechService.backendStatuses[speechService.selectedBackendID]?.isReady ?? false)
    }

    private func beginCommentFromCurrentSelection() {
        guard readerViewModel.selectedRange != nil else { return }
        commentDraft = ""
        showingCommentSheet = true
    }

    private func saveComment() {
        guard
            let range = readerViewModel.selectedRange,
            range.length > 0
        else {
            showingCommentSheet = false
            return
        }

        let note = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }

        let comment = ArticleComment(
            articleID: article.id,
            selectedText: readerViewModel.selectedText.trimmingCharacters(in: .whitespacesAndNewlines),
            noteBody: note,
            startOffset: range.location,
            endOffset: range.location + range.length
        )
        modelContext.insert(comment)
        article.updatedAt = .now
        readerViewModel.clearSelection()
        commentDraft = ""
        showingCommentSheet = false
    }
}

private struct PlayerBar: View {
    @Environment(SpeechPlaybackService.self) private var speechService
    @Environment(ReaderViewModel.self) private var readerViewModel

    let article: Article
    @State private var scrubProgress = 0.0
    @State private var isScrubbing = false
    @State private var showingVoiceSettings = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(timeString(currentPlaybackOffset))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ReaderTheme.secondaryText)
                    .frame(width: 58, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { scrubProgress },
                        set: { scrubProgress = $0 }
                    ),
                    in: 0...1,
                    onEditingChanged: handleScrubbingChanged
                )

                Text(timeString(totalDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ReaderTheme.secondaryText)
                    .frame(width: 58, alignment: .trailing)
            }

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(article.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(readerSubtitle)
                        .font(.caption)
                        .foregroundStyle(ReaderTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    speechService.seek(by: -30, in: article)
                } label: {
                    Image(systemName: "gobackward.30")
                }
                .buttonStyle(.plain)

                Button {
                    speechService.togglePlayback(for: article)
                } label: {
                    Image(systemName: playbackIconName)
                        .font(.system(size: 32))
                }
                .buttonStyle(.plain)

                Button {
                    speechService.seek(by: 30, in: article)
                } label: {
                    Image(systemName: "goforward.30")
                }
                .buttonStyle(.plain)

                Button {
                    showingVoiceSettings.toggle()
                } label: {
                    Label("Voice & Speed", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showingVoiceSettings, arrowEdge: .top) {
                    VoiceSettingsPopover(article: article)
                        .environment(speechService)
                        .padding(20)
                }
            }

        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(minHeight: 108)
        .onAppear {
            syncScrubber()
        }
        .onChange(of: speechService.currentProgress) { _, _ in
            syncScrubber()
        }
        .onChange(of: article.lastReadPosition) { _, _ in
            syncScrubber()
        }
    }

    private var currentPlaybackOffset: TimeInterval {
        speechService.currentArticleID == article.id ? speechService.currentPlaybackOffset : article.lastPlaybackOffset
    }

    private var currentProgressValue: Double {
        speechService.currentArticleID == article.id ? speechService.currentProgress : speechService.progress(for: article.lastReadPosition, in: article)
    }

    private var totalDuration: TimeInterval {
        speechService.totalDuration(for: article)
    }

    private var playbackIconName: String {
        if speechService.isStartingPlayback {
            return "stop.circle.fill"
        }
        return speechService.isPlaying ? "pause.circle.fill" : "play.circle.fill"
    }

    private var readerSubtitle: String {
        let voiceName = speechService.availableVoices.first(where: { $0.id == speechService.selectedVoiceID })?.name ?? "Voice"
        if let index = readerViewModel.activeParagraphIndex {
            return "Paragraph \(index + 1) · \(speechService.selectedBackendID.displayName) · \(voiceName) · \(String(format: "%.2fx", speechService.speed))"
        }
        return "\(article.displaySource) · \(speechService.selectedBackendID.displayName) · \(voiceName) · \(String(format: "%.2fx", speechService.speed))"
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private func handleScrubbingChanged(_ editing: Bool) {
        isScrubbing = editing
        if !editing {
            speechService.seek(toProgress: scrubProgress, in: article)
        }
    }

    private func syncScrubber() {
        guard !isScrubbing else { return }
        scrubProgress = currentProgressValue
    }
}

private struct SelectionActionBar: View {
    let selectedText: String
    let onHighlight: () -> Void
    let onComment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedText)
                .font(.footnote)
                .foregroundStyle(ReaderTheme.secondaryText)
                .lineLimit(3)

            HStack(spacing: 10) {
                Button {
                    onHighlight()
                } label: {
                    Label("Highlight", systemImage: "highlighter")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onComment()
                } label: {
                    Label("Add Note", systemImage: "text.bubble")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ReaderTheme.selectionSurface)
        )
    }
}

private struct VoiceSettingsPopover: View {
    @Environment(SpeechPlaybackService.self) private var speechService

    let article: Article
    @State private var draftBackendID: SpeechBackendID = .kokoro
    @State private var draftVoiceID: String = ""
    @State private var draftSpeed: Double = SpeechPlaybackService.defaultSpeed
    @State private var didSeedDraft = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice & Speed")
                .font(.system(size: 22, weight: .bold, design: .serif))

            Picker("Model", selection: backendBinding) {
                ForEach(speechService.availableBackends) { backend in
                    Text(backend.title).tag(backend.id)
                }
            }

            Picker("Voice", selection: voiceBinding) {
                ForEach(draftVoices) { voice in
                    Text(voice.displayLabel).tag(voice.id)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Playback speed")
                    Spacer()
                    Text(String(format: "%.2fx", draftSpeed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ReaderTheme.secondaryText)
                }
                Slider(value: speedBinding, in: 0.75...2.0, step: 0.25)
            }

            if let status = speechService.backendStatuses[draftBackendID] {
                Text(status.message)
                    .font(.caption)
                    .foregroundStyle(ReaderTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 320)
        .onAppear {
            seedDraftIfNeeded()
        }
        .onChange(of: draftBackendID) { _, newValue in
            if !draftVoices.contains(where: { $0.id == draftVoiceID }) {
                draftVoiceID = defaultVoiceID(for: newValue)
            }
        }
        .onDisappear {
            applyDraftIfNeeded()
        }
    }

    private var backendBinding: Binding<SpeechBackendID> {
        Binding(
            get: { draftBackendID },
            set: { draftBackendID = $0 }
        )
    }

    private var voiceBinding: Binding<String> {
        Binding(
            get: { draftVoiceID },
            set: { draftVoiceID = $0 }
        )
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: { draftSpeed },
            set: { draftSpeed = $0 }
        )
    }

    private var draftVoices: [VoiceOption] {
        LocalModelCatalog.profile(for: draftBackendID)?.voices ?? []
    }

    private func seedDraftIfNeeded() {
        guard !didSeedDraft else { return }
        didSeedDraft = true
        draftBackendID = speechService.selectedBackendID
        draftSpeed = speechService.speed
        draftVoiceID = speechService.selectedVoiceID
        if !draftVoices.contains(where: { $0.id == draftVoiceID }) {
            draftVoiceID = defaultVoiceID(for: draftBackendID)
        }
    }

    private func applyDraftIfNeeded() {
        guard didSeedDraft else { return }

        if draftBackendID != speechService.selectedBackendID {
            speechService.updateBackend(draftBackendID, for: article)
        }

        let resolvedVoiceID = draftVoices.contains(where: { $0.id == draftVoiceID })
            ? draftVoiceID
            : defaultVoiceID(for: draftBackendID)

        if !resolvedVoiceID.isEmpty, resolvedVoiceID != speechService.selectedVoiceID {
            speechService.updateVoice(resolvedVoiceID, for: article)
        }

        if draftSpeed != speechService.speed {
            speechService.updateSpeed(draftSpeed, for: article)
        }
    }

    private func defaultVoiceID(for backendID: SpeechBackendID) -> String {
        LocalModelCatalog.profile(for: backendID)?.voices.first?.id ?? ""
    }
}

private struct NewArticleSheet: View {
    private enum Field: Hashable {
        case title
        case body
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SpeechPlaybackService.self) private var speechService

    @State private var title = ""
    @State private var sourceLabel = ""
    @State private var bodyText = ""
    @FocusState private var focusedField: Field?

    private var normalizedPreview: NormalizedArticleText {
        ArticleTextProcessor.normalize(title: title, sourceLabel: sourceLabel, bodyText: bodyText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Article")
                .font(.system(size: 28, weight: .bold, design: .serif))

            VStack(alignment: .leading, spacing: 12) {
                TextField("Optional title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .title)

                TextField("Optional source or X headline", text: $sourceLabel)
                    .textFieldStyle(.roundedBorder)

                TextEditor(text: $bodyText)
                    .font(.body)
                    .focused($focusedField, equals: .body)
                    .padding(10)
                    .frame(minHeight: 340)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            }

            HStack {
                Label("\(normalizedPreview.estimatedReadingMinutes) min read", systemImage: "clock")
                    .foregroundStyle(ReaderTheme.secondaryText)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save Article") {
                    saveArticle()
                }
                .buttonStyle(.borderedProminent)
                .disabled(normalizedPreview.bodyText.count < 40)
            }
        }
        .padding(26)
        .frame(width: 760, height: 620)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                focusedField = .title
            }
        }
    }

    private func saveArticle() {
        let normalized = normalizedPreview
        let article = Article(
            title: normalized.title,
            sourceLabel: normalized.sourceLabel,
            bodyText: normalized.bodyText,
            estimatedReadingMinutes: normalized.estimatedReadingMinutes,
            lastBackendIdentifier: speechService.selectedBackendID.rawValue,
            lastVoiceIdentifier: speechService.selectedVoiceID,
            lastSpeed: SpeechPlaybackService.defaultSpeed
        )

        modelContext.insert(article)
        dismiss()
    }
}

private struct ModelStatusStrip: View {
    @Environment(SpeechPlaybackService.self) private var speechService

    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Local model setup")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ReaderTheme.secondaryText)

            HStack(spacing: 12) {
                ForEach(speechService.availableBackends) { backend in
                    ModelStatusCard(article: article, backend: backend)
                }
            }
        }
    }
}

private struct ModelStatusCard: View {
    @Environment(SpeechPlaybackService.self) private var speechService

    let article: Article
    let backend: SpeechBackendOption

    private var status: SpeechEngineStatus {
        speechService.backendStatuses[backend.id] ?? SpeechEngineStatus(message: backend.subtitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(backend.title)
                        .font(.subheadline.weight(.semibold))
                    Text(backend.subtitle)
                        .font(.caption)
                        .foregroundStyle(ReaderTheme.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
                if speechService.selectedBackendID == backend.id {
                    Text("Selected")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                }
            }

            Text(status.message)
                .font(.caption)
                .foregroundStyle(ReaderTheme.secondaryText)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if status.isPreparing {
                ProgressView(value: max(status.progress, 0.05))
                    .tint(.accentColor)
            } else {
                ProgressView(value: status.isReady ? 1 : 0)
                    .tint(status.isReady ? .green : .secondary.opacity(0.5))
            }

            HStack(spacing: 8) {
                Button(status.isReady ? "Re-check" : "Download") {
                    Task {
                        try? await speechService.prepareBackend(backend.id)
                    }
                }
                .buttonStyle(.bordered)

                Button("Use") {
                    speechService.updateBackend(backend.id, for: article)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(speechService.selectedBackendID == backend.id ? Color.accentColor.opacity(0.26) : ReaderTheme.border, lineWidth: 1)
        )
    }
}

private struct CommentComposerSheet: View {
    let article: Article
    let selectedText: String
    @Binding var draft: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Note")
                .font(.system(size: 28, weight: .bold, design: .serif))

            Text(article.title)
                .font(.headline)
                .foregroundStyle(ReaderTheme.secondaryText)
                .lineLimit(2)

            if !selectedText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected passage")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ReaderTheme.secondaryText)
                    Text(selectedText)
                        .font(.body)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(ReaderTheme.selectionSurface)
                        )
                }
            }

            TextEditor(text: $draft)
                .font(.body)
                .padding(10)
                .frame(minHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(ReaderTheme.border, lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save Note", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26)
        .frame(width: 560, height: 430)
    }
}

private struct AnnotationReviewSheet: View {
    let article: Article
    let highlights: [Highlight]
    let comments: [ArticleComment]
    let initialTab: AnnotationTab
    let timestampLabelForOffset: (Int) -> String
    let onJump: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: AnnotationTab

    init(
        article: Article,
        highlights: [Highlight],
        comments: [ArticleComment],
        initialTab: AnnotationTab,
        timestampLabelForOffset: @escaping (Int) -> String,
        onJump: @escaping (Int) -> Void
    ) {
        self.article = article
        self.highlights = highlights
        self.comments = comments
        self.initialTab = initialTab
        self.timestampLabelForOffset = timestampLabelForOffset
        self.onJump = onJump
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Highlights & Notes")
                .font(.system(size: 28, weight: .bold, design: .serif))

            Picker("Annotations", selection: $selectedTab) {
                Text("Highlights (\(highlights.count))").tag(AnnotationTab.highlights)
                Text("Notes (\(comments.count))").tag(AnnotationTab.notes)
            }
            .pickerStyle(.segmented)

            Group {
                if selectedTab == .highlights {
                    annotationList(
                        rows: highlights.map {
                            AnnotationRowModel(
                                id: $0.id,
                                title: $0.selectedText,
                                detail: "Highlight",
                                timestamp: timestampLabelForOffset($0.startOffset),
                                offset: $0.startOffset,
                                createdAt: $0.createdAt
                            )
                        },
                        emptyTitle: "No highlights yet",
                        emptyDescription: "Highlight a passage in the reader to build a reviewable list."
                    )
                } else {
                    annotationList(
                        rows: comments.map {
                            AnnotationRowModel(
                                id: $0.id,
                                title: $0.selectedText,
                                detail: $0.noteBody,
                                timestamp: timestampLabelForOffset($0.startOffset),
                                offset: $0.startOffset,
                                createdAt: $0.createdAt
                            )
                        },
                        emptyTitle: "No notes yet",
                        emptyDescription: "Right-click a selected passage in the reader and choose Add Note."
                    )
                }
            }

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
        }
        .padding(26)
        .frame(width: 720, height: 560)
    }

    @ViewBuilder
    private func annotationList(rows: [AnnotationRowModel], emptyTitle: String, emptyDescription: String) -> some View {
        if rows.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: "tray", description: Text(emptyDescription))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(rows) { row in
                        Button {
                            onJump(row.offset)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(row.timestamp)
                                        .font(.caption.monospacedDigit())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(ReaderTheme.timestampChip))
                                        .foregroundStyle(ReaderTheme.timestampText)
                                    Spacer()
                                    if let createdAt = row.createdAt {
                                        Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(ReaderTheme.secondaryText)
                                    }
                                }

                                Text(row.title)
                                    .font(.headline)
                                    .foregroundStyle(ReaderTheme.primaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(4)

                                Text(row.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(ReaderTheme.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(ReaderTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct AnnotationRowModel: Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let timestamp: String
    let offset: Int
    var createdAt: Date? = nil
}
