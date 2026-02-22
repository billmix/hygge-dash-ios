import SwiftUI

enum HyggeTheme {
    // Core backgrounds
    static let background = Color(red: 0.06, green: 0.07, blue: 0.06)       // #0f120f
    static let cardBackground = Color(red: 0.10, green: 0.12, blue: 0.10)   // #1a1f1a
    static let cardBackgroundLight = Color(red: 0.13, green: 0.16, blue: 0.13) // #212821

    // Accent
    static let accent = Color(red: 0.20, green: 0.78, blue: 0.35)           // #34c759
    static let accentDim = Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.15)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.5)
    static let textTertiary = Color.white.opacity(0.3)

    // Semantic
    static let destructive = Color(red: 0.90, green: 0.25, blue: 0.20)
    static let warning = Color.orange
}
