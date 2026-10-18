import AppKit
import Config

/// Records a key chord via a local `NSEvent` monitor (B19; no event tap).
@MainActor
final class ShortcutRecorderView: NSView {
    private let field = NSTextField(labelWithString: "Click, then press keys")
    private var monitor: Any?
    var chord: KeyChord? {
        didSet { refresh() }
    }
    var onChange: ((KeyChord?) -> Void)?
    var conflictText: String? {
        didSet { conflictLabel.stringValue = conflictText ?? "" }
    }

    private let conflictLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        field.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        field.translatesAutoresizingMaskIntoConstraints = false
        conflictLabel.font = NSFont.systemFont(ofSize: 11)
        conflictLabel.textColor = .systemOrange
        conflictLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(field)
        addSubview(conflictLabel)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            field.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            conflictLabel.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            conflictLabel.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            conflictLabel.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 2),
            conflictLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(beginRecording))
        addGestureRecognizer(click)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        // deinit is nonisolated; clear monitor on main if needed via stopRecording from outside.
    }

    func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    @objc private func beginRecording() {
        stopRecording()
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        field.stringValue = "Recording…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.capture(event)
            return nil
        }
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 { // escape
            stopRecording()
            refresh()
            return
        }
        var mods = ModifierSet()
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        mods.control = flags.contains(.control)
        mods.option = flags.contains(.option)
        mods.shift = flags.contains(.shift)
        mods.command = flags.contains(.command)

        guard let key = keyName(from: event) else { return }
        let recorded = KeyChord(modifiers: mods, key: key)
        chord = recorded
        onChange?(recorded)
        stopRecording()
    }

    private func refresh() {
        if let chord {
            field.stringValue = chord.description
        } else {
            field.stringValue = "Click, then press keys"
        }
    }

    private func keyName(from event: NSEvent) -> String? {
        // Reuse US-layout names aligned with KeyChord.
        switch Int(event.keyCode) {
        case 36: return "enter"
        case 48: return "tab"
        case 49: return "space"
        case 53: return "escape"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        case 33: return "left-bracket"
        case 30: return "right-bracket"
        default:
            guard let chars = event.charactersIgnoringModifiers?.lowercased(),
                  let first = chars.first,
                  first.isLetter || first.isNumber else { return nil }
            return String(first)
        }
    }
}
