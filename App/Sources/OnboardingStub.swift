import AppKit

/// Minimal onboarding copy stub for P7. Full flow lands in P9.
/// Includes Screen Recording / recording-indicator disclosure (PLAN §7 / P7).
@MainActor
enum OnboardingStub {
    /// UserDefaults key for "onboarding completed" (app/UI state only).
    static let completedKey = "lattice.onboarding.completed"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    /// Short screens used by a future wizard; recording-indicator note is required for P7.
    static let screens: [OnboardingScreen] = [
        OnboardingScreen(
            title: "Welcome to Lattice",
            body: "Lattice arranges your windows into a nestable layout with workspaces, zoom, and an overview."
        ),
        OnboardingScreen(
            title: "Accessibility",
            body: "Lattice needs Accessibility permission to move and resize windows. You can grant it in System Settings."
        ),
        OnboardingScreen(
            title: "No Input Monitoring",
            body: "Lattice does not require Input Monitoring. Keyboard shortcuts use an Accessibility-trusted event tap."
        ),
        OnboardingScreen(
            title: "Optional Screen Recording",
            body: """
            Overview window previews are optional and use Screen Recording. When enabled, macOS shows the \
            orange recording indicator in the menu bar while Lattice captures previews. Previews stay in \
            memory and are never written to disk. You can turn previews off anytime with overview-previews = 'off'.
            """
        ),
        OnboardingScreen(
            title: "Ready",
            body: "Open the Lattice menu-bar icon for Float All and Quit. Configure behaviour in ~/.config/lattice/lattice.toml."
        ),
    ]

    /// Recording-indicator disclosure text (stable for tests / copy review).
    static var recordingIndicatorDisclosure: String {
        screens.first(where: { $0.title == "Optional Screen Recording" })?.body ?? ""
    }
}

struct OnboardingScreen: Equatable, Sendable {
    var title: String
    var body: String
}
