import AppKit
import CoreGraphics
import Foundation
import Platform

/// Enumerate displays keyed by `CGDisplayCreateUUIDFromDisplayID` string.
public enum MacDisplays {
    public static func listDisplays() -> [DisplayRef] {
        var refs: [DisplayRef] = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let uuid = uuidString(for: displayID) ?? "display-\(displayID)"
            let frame = rectCodable(screen.frame)
            let visible = rectCodable(screen.visibleFrame)
            let name = screen.localizedName
            refs.append(DisplayRef(uuid: uuid, name: name, frame: frame, visibleFrame: visible))
        }
        return refs
    }

    /// `CGDisplayCreateUUIDFromDisplayID` → string (empty / nil if unavailable).
    public static func uuidString(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        let cf = CFUUIDCreateString(nil, uuid) as String?
        return cf
    }

    public static func rectCodable(_ rect: CGRect) -> CGRectCodable {
        CGRectCodable(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }

    public static func cgRect(_ rect: CGRectCodable) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
