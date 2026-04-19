import AppKit
import SwiftUI

enum ReaderTheme {
    static let paper = Color(nsColor: paperNSColor)
    static let pageGlow = Color(nsColor: pageGlowNSColor)
    static let primaryText = Color(nsColor: primaryTextNSColor)
    static let headingText = Color(nsColor: headingTextNSColor)
    static let secondaryText = Color(nsColor: secondaryTextNSColor)
    static let selectionSurface = Color(nsColor: selectionSurfaceNSColor)
    static let border = Color(nsColor: borderNSColor)
    static let panelSurface = Color(nsColor: panelSurfaceNSColor)
    static let timestampChip = Color(nsColor: timestampChipNSColor)
    static let timestampText = Color(nsColor: timestampTextNSColor)
    static let commentUnderline = Color(nsColor: commentUnderlineNSColor)

    static let paperNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1)
        }
        return NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.93, alpha: 1)
    }

    static let pageGlowNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.22, alpha: 1)
        }
        return NSColor(calibratedRed: 1.0, green: 0.995, blue: 0.98, alpha: 1)
    }

    static let primaryTextNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.90, alpha: 1)
        }
        return NSColor(calibratedRed: 0.12, green: 0.11, blue: 0.10, alpha: 1)
    }

    static let headingTextNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.88, alpha: 1)
        }
        return NSColor(calibratedRed: 0.19, green: 0.14, blue: 0.10, alpha: 1)
    }

    static let secondaryTextNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 0.72, green: 0.71, blue: 0.68, alpha: 1)
        }
        return NSColor(calibratedRed: 0.39, green: 0.35, blue: 0.30, alpha: 1)
    }

    static let savedHighlightNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.systemYellow.withAlphaComponent(0.26)
        }
        return NSColor.systemYellow.withAlphaComponent(0.32)
    }

    static let activeParagraphNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.systemBlue.withAlphaComponent(0.22)
        }
        return NSColor.systemBlue.withAlphaComponent(0.11)
    }

    static let activeWordNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.systemTeal.withAlphaComponent(0.34)
        }
        return NSColor.systemBlue.withAlphaComponent(0.28)
    }

    static let sectionBreakNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.systemOrange.withAlphaComponent(0.08)
        }
        return NSColor.systemOrange.withAlphaComponent(0.06)
    }

    static let selectionSurfaceNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.08)
        }
        return NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.04)
    }

    static let panelSurfaceNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.055)
        }
        return NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.62)
    }

    static let borderNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.09)
        }
        return NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.08)
    }

    static let timestampChipNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 0.30, green: 0.27, blue: 0.20, alpha: 0.95)
        }
        return NSColor(calibratedRed: 0.93, green: 0.89, blue: 0.80, alpha: 0.98)
    }

    static let timestampTextNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.86, alpha: 1)
        }
        return NSColor(calibratedRed: 0.27, green: 0.21, blue: 0.14, alpha: 1)
    }

    static let commentUnderlineNSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.systemPink.withAlphaComponent(0.9)
        }
        return NSColor.systemRed.withAlphaComponent(0.75)
    }
}
