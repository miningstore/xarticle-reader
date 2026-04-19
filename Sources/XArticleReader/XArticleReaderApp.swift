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
        NSApp.applicationIconImage = AppIconFactory.makeIcon()
        NSApp.setActivationPolicy(.regular)
        bringAppToFront()
        DispatchQueue.main.async { [weak self] in
            self?.bringAppToFront()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.bringAppToFront()
        }
    }

    private func bringAppToFront() {
        NSApp.unhide(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.collectionBehavior.remove(.transient)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}

private enum AppIconFactory {
    static func makeIcon(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let bounds = NSRect(x: 0, y: 0, width: size, height: size)
        let cornerRadius = size * 0.22
        let basePath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)

        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.09, green: 0.15, blue: 0.28, alpha: 1.0),
            NSColor(calibratedRed: 0.12, green: 0.28, blue: 0.50, alpha: 1.0),
            NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.72, alpha: 1.0),
        ])!
        gradient.draw(in: basePath, angle: -90)

        NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
        let glow = NSBezierPath(ovalIn: NSRect(x: size * 0.10, y: size * 0.54, width: size * 0.78, height: size * 0.34))
        glow.fill()

        let pageRect = NSRect(x: size * 0.18, y: size * 0.16, width: size * 0.64, height: size * 0.68)
        let pagePath = NSBezierPath(roundedRect: pageRect, xRadius: size * 0.06, yRadius: size * 0.06)
        NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.90, alpha: 1.0).setFill()
        pagePath.fill()

        let foldPath = NSBezierPath()
        foldPath.move(to: NSPoint(x: pageRect.maxX - size * 0.16, y: pageRect.maxY))
        foldPath.line(to: NSPoint(x: pageRect.maxX, y: pageRect.maxY - size * 0.16))
        foldPath.line(to: NSPoint(x: pageRect.maxX - size * 0.16, y: pageRect.maxY - size * 0.16))
        foldPath.close()
        NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.95, alpha: 1.0).setFill()
        foldPath.fill()

        let waveformColor = NSColor(calibratedRed: 0.15, green: 0.30, blue: 0.48, alpha: 1.0)
        waveformColor.setStroke()
        let waveform = NSBezierPath()
        waveform.lineWidth = size * 0.032
        let startX = pageRect.minX + size * 0.10
        let baseY = pageRect.midY - size * 0.02
        waveform.move(to: NSPoint(x: startX, y: baseY))
        waveform.line(to: NSPoint(x: startX + size * 0.07, y: baseY))
        waveform.line(to: NSPoint(x: startX + size * 0.12, y: baseY + size * 0.10))
        waveform.line(to: NSPoint(x: startX + size * 0.18, y: baseY - size * 0.08))
        waveform.line(to: NSPoint(x: startX + size * 0.25, y: baseY + size * 0.15))
        waveform.line(to: NSPoint(x: startX + size * 0.33, y: baseY - size * 0.05))
        waveform.line(to: NSPoint(x: startX + size * 0.42, y: baseY + size * 0.06))
        waveform.line(to: NSPoint(x: startX + size * 0.52, y: baseY + size * 0.06))
        waveform.stroke()

        let textLineColor = NSColor(calibratedRed: 0.43, green: 0.54, blue: 0.66, alpha: 0.95)
        textLineColor.setFill()
        for index in 0..<3 {
            let y = pageRect.minY + size * (0.16 + CGFloat(index) * 0.095)
            let line = NSBezierPath(roundedRect: NSRect(x: pageRect.minX + size * 0.10, y: y, width: size * (0.36 - CGFloat(index) * 0.04), height: size * 0.028), xRadius: size * 0.014, yRadius: size * 0.014)
            line.fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
