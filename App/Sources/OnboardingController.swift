import AppKit
import Platform
import PlatformMac

/// Native multi-step onboarding (PLAN §7): Welcome → Accessibility → Input Monitoring note →
/// Optional Screen Recording → Quick tutorial.
@MainActor
final class OnboardingController: NSWindowController {
    /// UserDefaults key for "onboarding completed" (app/UI state only).
    static let completedKey = "lattice.onboarding.completed"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    /// Recording-indicator disclosure (stable for tests / copy review).
    static let recordingIndicatorDisclosure = """
    Lattice optionally uses Screen Recording to take still pictures of windows while they move. \
    When enabled, macOS shows the orange recording indicator in the menu bar during those captures. \
    Pictures stay in memory and are never written to disk. Without Screen Recording, Lattice uses \
    coloured boxes with app icons instead. After granting Screen Recording, Lattice must relaunch \
    for the permission to take effect.
    """

    private enum Step: Int, CaseIterable {
        case welcome
        case accessibility
        case inputMonitoring
        case screenRecording
        case tutorial
    }

    private let permissions: MacPermissions
    private let inputSafetyNet: InputSafetyNetState
    private var step: Step = .welcome
    private var pollTimer: Timer?
    private var titleLabel: NSTextField!
    private var bodyLabel: NSTextField!
    private var primaryButton: NSButton!
    private var secondaryButton: NSButton!
    private var skipButton: NSButton!
    private var onFinished: (() -> Void)?

    init(
        permissions: MacPermissions = MacPermissions(),
        inputSafetyNet: InputSafetyNetState = .full,
        onFinished: (() -> Void)? = nil
    ) {
        self.permissions = permissions
        self.inputSafetyNet = inputSafetyNet
        self.onFinished = onFinished
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Lattice"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        let effect = NSVisualEffectView(frame: .zero)
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            effect.isHidden = true
            content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }

        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyLabel = NSTextField(wrappingLabelWithString: "")
        bodyLabel.font = NSFont.systemFont(ofSize: 13)
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.maximumNumberOfLines = 0

        primaryButton = NSButton(title: "Continue", target: self, action: #selector(primaryAction))
        primaryButton.keyEquivalent = "\r"
        secondaryButton = NSButton(title: "Open Settings", target: self, action: #selector(secondaryAction))
        skipButton = NSButton(title: "Skip", target: self, action: #selector(skipStep))

        let buttons = NSStackView(views: [skipButton, secondaryButton, primaryButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(effect)
        content.addSubview(titleLabel)
        content.addSubview(bodyLabel)
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            effect.topAnchor.constraint(equalTo: content.topAnchor),
            effect.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),

            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),

            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
        ])
    }

    private func render() {
        pollTimer?.invalidate()
        pollTimer = nil
        secondaryButton.isHidden = true
        skipButton.isHidden = true

        switch step {
        case .welcome:
            titleLabel.stringValue = "Welcome to Lattice"
            bodyLabel.stringValue =
                "Lattice arranges your windows into a nestable layout with workspaces and a zoom camera."
            primaryButton.title = "Continue"
        case .accessibility:
            titleLabel.stringValue = "Accessibility"
            bodyLabel.stringValue =
                "Lattice needs Accessibility permission to move and resize windows. Grant it when prompted, or open System Settings."
            primaryButton.title = permissions.isAccessibilityTrusted ? "Continue" : "Grant Accessibility"
            secondaryButton.title = "Open Settings"
            secondaryButton.isHidden = false
            if !permissions.isAccessibilityTrusted {
                _ = permissions.requestAccessibilityTrust(prompt: true)
                startAccessibilityPoll()
            }
        case .inputMonitoring:
            titleLabel.stringValue = "Input Monitoring"
            if inputSafetyNet.reducedInputFeatures {
                bodyLabel.stringValue = """
                On this macOS version Lattice could not use a full event tap without Input Monitoring. \
                Modifier-drag, pinch-over-apps, and left/right modifier distinction are disabled. \
                Keyboard shortcuts use Carbon hotkeys instead.
                \(inputSafetyNet.notice.map { "\n\n\($0)" } ?? "")
                """
            } else {
                bodyLabel.stringValue =
                    "Lattice does not require Input Monitoring. Keyboard shortcuts use an Accessibility-trusted event tap."
            }
            primaryButton.title = "Continue"
        case .screenRecording:
            titleLabel.stringValue = "Optional Screen Recording"
            bodyLabel.stringValue = Self.recordingIndicatorDisclosure
            primaryButton.title = permissions.hasScreenRecordingAccess ? "Continue" : "Allow Screen Recording"
            secondaryButton.title = "Not now"
            secondaryButton.isHidden = false
            skipButton.isHidden = true
        case .tutorial:
            titleLabel.stringValue = "Quick tips"
            bodyLabel.stringValue = """
            • Use Alt+H/J/K/L to focus neighbouring windows, Alt+Shift+H/J/K/L to move them.
            • Open the Lattice menu-bar icon (rectangle.split.3x1) for Settings, Float All, and Quit.
            • Configure behaviour in ~/.config/lattice/lattice.toml — the Settings window can open it for you.
            """
            primaryButton.title = "Get started"
        }
    }

    private func startAccessibilityPoll() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.permissions.isAccessibilityTrusted {
                    self.pollTimer?.invalidate()
                    self.pollTimer = nil
                    self.advance()
                }
            }
        }
    }

    @objc private func primaryAction() {
        switch step {
        case .welcome:
            advance()
        case .accessibility:
            if permissions.isAccessibilityTrusted {
                advance()
            } else {
                _ = permissions.requestAccessibilityTrust(prompt: true)
                openAccessibilitySettings()
                startAccessibilityPoll()
            }
        case .inputMonitoring:
            advance()
        case .screenRecording:
            if permissions.hasScreenRecordingAccess {
                advance()
            } else {
                _ = permissions.requestScreenRecordingAccess()
                // Permission typically requires relaunch.
                Self.relaunchApp()
            }
        case .tutorial:
            finish()
        }
    }

    @objc private func secondaryAction() {
        switch step {
        case .accessibility:
            openAccessibilitySettings()
            startAccessibilityPoll()
        case .screenRecording:
            advance()
        default:
            break
        }
    }

    @objc private func skipStep() {
        advance()
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        step = next
        render()
    }

    private func finish() {
        pollTimer?.invalidate()
        Self.markCompleted()
        window?.close()
        onFinished?()
    }

    private func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.Settings.extension.PrivacySecurity?Privacy_Accessibility",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// Relaunch without `sh -c` string building (PLAN §7).
    static func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

/// Back-compat alias used by older asserts / tests.
@MainActor
enum OnboardingStub {
    static let completedKey = OnboardingController.completedKey
    static var isCompleted: Bool { OnboardingController.isCompleted }
    static func markCompleted() { OnboardingController.markCompleted() }
    static var recordingIndicatorDisclosure: String { OnboardingController.recordingIndicatorDisclosure }

    static let screens: [OnboardingScreen] = [
        OnboardingScreen(title: "Welcome to Lattice", body: "Lattice arranges your windows."),
        OnboardingScreen(title: "Accessibility", body: "Lattice needs Accessibility permission."),
        OnboardingScreen(title: "No Input Monitoring", body: "Lattice does not require Input Monitoring."),
        OnboardingScreen(title: "Optional Screen Recording", body: OnboardingController.recordingIndicatorDisclosure),
        OnboardingScreen(title: "Ready", body: "Open the Lattice menu-bar icon."),
    ]
}

struct OnboardingScreen: Equatable, Sendable {
    var title: String
    var body: String
}
