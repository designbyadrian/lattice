import Foundation
import LayoutModel
import Platform

extension CGRectCodable {
    public var asRect: Rect {
        Rect(x: x, y: y, width: width, height: height)
    }

    public init(_ rect: Rect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}

extension Rect {
    public var asCGRectCodable: CGRectCodable {
        CGRectCodable(self)
    }
}

extension WindowRef {
    public var asWindowID: WindowID {
        WindowID(
            cgWindowID: id == 0 ? nil : id,
            processID: pid,
            bundleID: bundleID,
            titleFingerprint: title
        )
    }
}

extension WindowID {
    /// Match a live platform window to this stable id.
    public func matches(_ ref: WindowRef) -> Bool {
        if let cg = cgWindowID, cg != 0, ref.id == cg { return true }
        return fingerprintMatches(ref.asWindowID)
    }
}
