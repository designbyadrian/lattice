import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Platform

/// CGWindowList + AX discovery with public-route matching.
public enum MacWindowDiscovery {
    /// Messaging timeout applied to each AX application element (~0.25 s per PLAN §6).
    public static let axMessagingTimeout: Float = 0.25

    public static func listManagedWindows(
        experimentalFlags: ExperimentalFlags = .default
    ) -> [Platform.WindowRef] {
        let cgSnapshots = copyCGWindowSnapshots()
        let axSnapshots = copyAXWindowSnapshots(timeout: axMessagingTimeout)
        _ = experimentalFlags // `axWindowID` fallback reserved for P10 via ExperimentalAXWindowID
        return WindowDiscoveryFilter.discoverWindows(
            cgWindows: cgSnapshots,
            axWindows: axSnapshots,
            bundleIDForPID: bundleID(for:),
            appNameForPID: appName(for:)
        )
    }

    // MARK: - CG

    public static func copyCGWindowSnapshots() -> [CGWindowInfoSnapshot] {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return info.compactMap { dict -> CGWindowInfoSnapshot? in
            guard let number = dict[kCGWindowNumber as String] as? NSNumber,
                  let pid = dict[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = dict[kCGWindowLayer as String] as? NSNumber
            else { return nil }

            let boundsDict = dict[kCGWindowBounds as String] as? [String: Any]
            let bounds = boundsFromCGDict(boundsDict) ?? .zero
            let onscreen: Bool
            if let flag = dict[kCGWindowIsOnscreen as String] as? NSNumber {
                onscreen = flag.boolValue
            } else {
                onscreen = true
            }

            return CGWindowInfoSnapshot(
                windowNumber: number.uint32Value,
                ownerPID: pid.int32Value,
                ownerName: dict[kCGWindowOwnerName as String] as? String,
                name: dict[kCGWindowName as String] as? String,
                layer: layer.intValue,
                bounds: bounds,
                isOnscreen: onscreen
            )
        }
    }

    // MARK: - AX

    public static func copyAXWindowSnapshots(timeout: Float = axMessagingTimeout) -> [AXWindowInfoSnapshot] {
        var result: [AXWindowInfoSnapshot] = []
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, timeout)

            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            guard err == .success, let windows = windowsRef as? [AXUIElement] else { continue }

            for window in windows {
                if let snap = snapshot(window: window, pid: pid) {
                    result.append(snap)
                }
            }
        }
        return result
    }

    public static func snapshot(window: AXUIElement, pid: Int32) -> AXWindowInfoSnapshot? {
        let title = stringAttribute(window, kAXTitleAttribute as CFString) ?? ""
        let role = stringAttribute(window, kAXRoleAttribute as CFString)
        let subrole = stringAttribute(window, kAXSubroleAttribute as CFString)
        let frame = frameAttribute(window) ?? .zero
        let minimized = boolAttribute(window, kAXMinimizedAttribute as CFString) ?? false
        let fullscreen = boolAttribute(window, "AXFullScreen" as CFString) ?? false
        return AXWindowInfoSnapshot(
            pid: pid,
            title: title,
            role: role,
            subrole: subrole,
            frame: frame,
            isMinimized: minimized,
            isFullscreen: fullscreen
        )
    }

    /// Resolve an AXUIElement for a known CG window via public pid+frame+title matching.
    public static func axElement(
        windowID: UInt32,
        pid: Int32,
        timeout: Float = axMessagingTimeout
    ) -> AXUIElement? {
        let cgList = copyCGWindowSnapshots()
        guard let cg = cgList.first(where: { $0.windowNumber == windowID && $0.ownerPID == pid }) else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, timeout)

        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement] else { return nil }

        let targetTitle = cg.name ?? ""
        for window in windows {
            guard let snap = snapshot(window: window, pid: pid) else { continue }
            if WindowDiscoveryFilter.matchCGWindow(for: snap, in: [cg]) != nil {
                return window
            }
            // Direct compare against known CG entry.
            if snap.title == targetTitle,
               snap.frame.isApproximatelyEqual(to: cg.bounds) {
                return window
            }
        }

        // Last resort: single standard window for this pid matching the id's frame.
        let standard = windows.compactMap { w -> (AXUIElement, AXWindowInfoSnapshot)? in
            guard let s = snapshot(window: w, pid: pid),
                  WindowDiscoveryFilter.isManageableAXWindow(s) else { return nil }
            return (w, s)
        }
        if standard.count == 1 { return standard[0].0 }
        return standard.first(where: { $0.1.frame.isApproximatelyEqual(to: cg.bounds) })?.0
    }

    // MARK: - Helpers

    private static func bundleID(for pid: Int32) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private static func appName(for pid: Int32) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    private static func boundsFromCGDict(_ dict: [String: Any]?) -> CGRectCodable? {
        guard let dict else { return nil }
        let x = (dict["X"] as? NSNumber)?.doubleValue ?? 0
        let y = (dict["Y"] as? NSNumber)?.doubleValue ?? 0
        let w = (dict["Width"] as? NSNumber)?.doubleValue ?? 0
        let h = (dict["Height"] as? NSNumber)?.doubleValue ?? 0
        return CGRectCodable(x: x, y: y, width: w, height: h)
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ name: CFString) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &ref) == .success else { return nil }
        if let num = ref as? NSNumber { return num.boolValue }
        return nil
    }

    private static func frameAttribute(_ element: AXUIElement) -> CGRectCodable? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        // AXValueGetValue is the public route for AXPosition / AXSize.
        if let pos = posRef {
            AXValueGetValue(pos as! AXValue, .cgPoint, &point)
        }
        if let sz = sizeRef {
            AXValueGetValue(sz as! AXValue, .cgSize, &size)
        }
        return CGRectCodable(x: point.x, y: point.y, width: size.width, height: size.height)
    }
}
