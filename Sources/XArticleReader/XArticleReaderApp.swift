import AppKit
import SwiftUI
import SwiftData

@main
struct XArticleReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var speechPlaybackService = SpeechPlaybackService()
    @State private var readerViewModel = ReaderViewModel()

    var body: some Scene {
        WindowGroup("XArticleReader") {
            ContentView()
                .environment(speechPlaybackService)
                .environment(readerViewModel)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .modelContainer(for: [Article.self, Highlight.self, ArticleComment.self])
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != currentPID {
            if app.localizedName == "XArticleReader" {
                app.forceTerminate()
            }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
