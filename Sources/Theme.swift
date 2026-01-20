import SwiftUI

struct Theme {
    static let navy = Color(nsColor: NSColor(name: "navy", dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0.05, green: 0.1, blue: 0.2, alpha: 1.0)
        } else {
            return NSColor(red: 0.1, green: 0.15, blue: 0.35, alpha: 1.0)
        }
    }))
    
    static let navyLight = Color(nsColor: NSColor(name: "navyLight", dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0.1, green: 0.15, blue: 0.3, alpha: 1.0)
        } else {
            return NSColor(red: 0.2, green: 0.25, blue: 0.45, alpha: 1.0)
        }
    }))
    
    static let copper = Color(nsColor: NSColor(name: "copper", dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0.8, green: 0.5, blue: 0.2, alpha: 1.0)
        } else {
            return NSColor(red: 0.65, green: 0.35, blue: 0.1, alpha: 1.0) // Darker in light mode for contrast
        }
    }))
    
    static let copperLight = Color(nsColor: NSColor(name: "copperLight", dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0.85, green: 0.6, blue: 0.3, alpha: 1.0)
        } else {
            return NSColor(red: 0.75, green: 0.45, blue: 0.2, alpha: 1.0)
        }
    }))
    
    // Semantic Colors
    static let bubbleUser = navy
    static let bubbleAssistant = Color(nsColor: NSColor(name: "bubbleAssistant", dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.1)
        } else {
            return NSColor.black.withAlphaComponent(0.05)
        }
    }))
    
    static let sidebarBackground = Color(nsColor: NSColor.controlBackgroundColor)
    
    // Typography Helpers
    static let headerFont: Font = .system(.title2, design: .serif).weight(.medium)
    static let subHeaderFont: Font = .system(.subheadline, design: .serif).weight(.medium)
    
    // Gradients
    static let accentGradient = LinearGradient(
        colors: [navy, navyLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    static let themeNavy = Theme.navy
    static let themeCopper = Theme.copper
}
