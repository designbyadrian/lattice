import Foundation
import Config

/// Border colour + frame math (testable without AppKit).
public enum BorderGeometry {
    public struct RGBA: Equatable, Sendable {
        public var r: Double
        public var g: Double
        public var b: Double
        public var a: Double

        public init(r: Double, g: Double, b: Double, a: Double = 1) {
            self.r = r
            self.g = g
            self.b = b
            self.a = a
        }
    }

    /// Resolve a configured colour. `accentRGBA` is supplied by the host (system accent).
    public static func resolve(
        _ color: BorderColor,
        accentRGBA: RGBA = RGBA(r: 0.0, g: 0.48, b: 1.0, a: 1)
    ) throws -> RGBA {
        switch color {
        case .accent:
            return accentRGBA
        case .hex(let raw):
            return try parseHex(raw)
        }
    }

    public static func parseHex(_ raw: String) throws -> RGBA {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#") else {
            throw ConfigError("border colour must be '#rrggbb', '#rrggbbaa', or 'accent'")
        }
        let hex = String(s.dropFirst())
        guard hex.count == 6 || hex.count == 8, hex.allSatisfy(\.isHexDigit) else {
            throw ConfigError("border colour must be '#rrggbb', '#rrggbbaa', or 'accent'")
        }
        func ch(_ i: Int) -> Double {
            let start = hex.index(hex.startIndex, offsetBy: i)
            let end = hex.index(start, offsetBy: 2)
            return Double(Int(hex[start..<end], radix: 16)!) / 255.0
        }
        let a = hex.count == 8 ? ch(6) : 1.0
        return RGBA(r: ch(0), g: ch(2), b: ch(4), a: a)
    }

    /// Increase Contrast bumps width by at least 2 points.
    public static func effectiveWidth(configured: Double, increaseContrast: Bool) -> Double {
        if increaseContrast {
            return max(configured + 2, configured)
        }
        return configured
    }

    /// Outer ring frame grown by `width` on each side around the window frame.
    public static func borderFrame(
        windowFrame: (x: Double, y: Double, width: Double, height: Double),
        width: Double
    ) -> (x: Double, y: Double, width: Double, height: Double) {
        (
            x: windowFrame.x - width,
            y: windowFrame.y - width,
            width: windowFrame.width + width * 2,
            height: windowFrame.height + width * 2
        )
    }

    /// Inset for the hollow (click-through) region inside the border ring.
    public static func innerHole(
        borderFrame: (x: Double, y: Double, width: Double, height: Double),
        width: Double
    ) -> (x: Double, y: Double, width: Double, height: Double) {
        (
            x: borderFrame.x + width,
            y: borderFrame.y + width,
            width: max(0, borderFrame.width - width * 2),
            height: max(0, borderFrame.height - width * 2)
        )
    }
}
