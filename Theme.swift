import SwiftUI

/// Brand theme matching Story Time Production viewer (`globals.css` + ST logo).
enum Theme {
    static let background = Color.black
    static let surface = Color(red: 0.03, green: 0.03, blue: 0.03)
    static let card = Color(red: 0.04, green: 0.04, blue: 0.04)
    static let foreground = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let muted = Color(red: 0.62, green: 0.62, blue: 0.62)
    static let border = Color.white.opacity(0.12)

    /// `--primary: 31 100% 56%` — orange brand accent
    static let accent = Color(red: 1.0, green: 0.575, blue: 0.12)
    /// `--accent: 39 100% 64%` — gold highlight
    static let accentGold = Color(red: 1.0, green: 0.77, blue: 0.28)
    static let accentSoft = accent.opacity(0.15)

    static let playButton = Color.white
    static let playButtonForeground = Color.black
    static let progressTrack = Color.white.opacity(0.25)
    static let navInactive = Color(red: 0.64, green: 0.64, blue: 0.64)

    static let profileColors: [Color] = [
        Color(red: 0.20, green: 0.45, blue: 0.95),
        Color(red: 0.95, green: 0.75, blue: 0.15),
        Color(red: 0.25, green: 0.70, blue: 0.55),
        Color(red: 0.90, green: 0.30, blue: 0.35),
        Color(red: 0.65, green: 0.40, blue: 0.90),
        Color(red: 0.95, green: 0.55, blue: 0.20),
    ]

    static func profileColor(for id: String) -> Color {
        let hash = abs(id.hashValue)
        return profileColors[hash % profileColors.count]
    }
}
