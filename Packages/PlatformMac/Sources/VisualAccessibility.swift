import AppKit

/// Shared hooks for Reduce Motion / Transparency / Increase Contrast (PLAN §7).
@MainActor
public enum VisualAccessibility {
    public static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    public static var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    /// Apply system material, or opaque window background under Reduce Transparency.
    public static func applyMaterial(
        _ material: NSVisualEffectView.Material,
        to effectView: NSVisualEffectView,
        fallbackLayer layer: CALayer?
    ) {
        if reduceTransparency {
            effectView.isHidden = true
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        } else {
            effectView.isHidden = false
            effectView.material = material
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    /// Outline width under Increase Contrast (borders / drop targets).
    public static func outlineWidth(base: CGFloat) -> CGFloat {
        increaseContrast ? max(base + 2, base * 1.5) : base
    }

    /// Accent colour for focus / selection (follows light/dark automatically).
    public static var accent: NSColor { .controlAccentColor }
}
