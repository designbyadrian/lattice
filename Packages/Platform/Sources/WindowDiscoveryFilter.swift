import Foundation

// MARK: - Recorded-style snapshots (fixture / test friendly)

/// One entry shaped like `CGWindowListCopyWindowInfo` public keys.
public struct CGWindowInfoSnapshot: Hashable, Sendable, Codable {
    public var windowNumber: UInt32
    public var ownerPID: Int32
    public var ownerName: String?
    public var name: String?
    public var layer: Int
    public var bounds: CGRectCodable
    public var isOnscreen: Bool

    public init(
        windowNumber: UInt32,
        ownerPID: Int32,
        ownerName: String? = nil,
        name: String? = nil,
        layer: Int,
        bounds: CGRectCodable,
        isOnscreen: Bool = true
    ) {
        self.windowNumber = windowNumber
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.name = name
        self.layer = layer
        self.bounds = bounds
        self.isOnscreen = isOnscreen
    }
}

/// One AX window attribute dump used for filtering and CG matching.
public struct AXWindowInfoSnapshot: Hashable, Sendable, Codable {
    public var pid: Int32
    public var title: String
    public var role: String?
    public var subrole: String?
    public var frame: CGRectCodable
    public var isMinimized: Bool
    public var isFullscreen: Bool

    public init(
        pid: Int32,
        title: String,
        role: String? = "AXWindow",
        subrole: String? = nil,
        frame: CGRectCodable,
        isMinimized: Bool = false,
        isFullscreen: Bool = false
    ) {
        self.pid = pid
        self.title = title
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
    }
}

/// Pure discovery filtering + public-route AX↔CG matching (no AppKit).
public enum WindowDiscoveryFilter {
    /// Subroles that must never be tiled (sheets / dialogs / popovers / floaters).
    public static let ignoredAXSubroles: Set<String> = [
        "AXDialog",
        "AXSystemDialog",
        "AXFloatingWindow",
        "AXSystemFloatingWindow",
        "AXUnknown",
    ]

    /// Roles that indicate transient UI even when subrole is missing.
    public static let ignoredAXRoles: Set<String> = [
        "AXSheet",
        "AXPopover",
        "AXDialog",
    ]

    /// CG layer-0 on-screen windows only (matches `.optionOnScreenOnly` + layer filter).
    public static func isCandidateCGWindow(_ info: CGWindowInfoSnapshot) -> Bool {
        info.isOnscreen && info.layer == 0
    }

    public static func filterCGWindows(_ infos: [CGWindowInfoSnapshot]) -> [CGWindowInfoSnapshot] {
        infos.filter(isCandidateCGWindow)
    }

    /// Accept only standard windows; reject sheets, dialogs, popovers.
    public static func isManageableAXWindow(_ info: AXWindowInfoSnapshot) -> Bool {
        if let role = info.role, ignoredAXRoles.contains(role) {
            return false
        }
        if let subrole = info.subrole {
            if ignoredAXSubroles.contains(subrole) {
                return false
            }
            return subrole == "AXStandardWindow"
        }
        // Missing subrole: only keep plain AXWindow (conservative).
        return info.role == "AXWindow" || info.role == nil
    }

    public static func filterAXWindows(_ infos: [AXWindowInfoSnapshot]) -> [AXWindowInfoSnapshot] {
        infos.filter(isManageableAXWindow)
    }

    /// Public matching route: pid + frame + title.
    public static func matchCGWindow(
        for ax: AXWindowInfoSnapshot,
        in cgWindows: [CGWindowInfoSnapshot],
        frameTolerance: Double = 2.0
    ) -> CGWindowInfoSnapshot? {
        let candidates = cgWindows.filter { cg in
            isCandidateCGWindow(cg) && cg.ownerPID == ax.pid
        }
        if candidates.isEmpty { return nil }

        let title = ax.title
        let exactTitle = candidates.filter { ($0.name ?? "") == title }
        let pool = exactTitle.isEmpty ? candidates : exactTitle

        if let hit = pool.first(where: { $0.bounds.isApproximatelyEqual(to: ax.frame, tolerance: frameTolerance) }) {
            return hit
        }

        // Title-only fallback among same-pid layer-0 windows when frames disagree slightly.
        if exactTitle.count == 1 {
            return exactTitle[0]
        }
        return nil
    }

    /// Build managed `WindowRef`s from paired snapshots.
    public static func discoverWindows(
        cgWindows: [CGWindowInfoSnapshot],
        axWindows: [AXWindowInfoSnapshot],
        bundleIDForPID: (Int32) -> String? = { _ in nil },
        appNameForPID: (Int32) -> String? = { _ in nil }
    ) -> [WindowRef] {
        let cg = filterCGWindows(cgWindows)
        let ax = filterAXWindows(axWindows)
        var refs: [WindowRef] = []
        var usedCG = Set<UInt32>()

        for axInfo in ax {
            guard let matched = matchCGWindow(for: axInfo, in: cg) else { continue }
            guard !usedCG.contains(matched.windowNumber) else { continue }
            usedCG.insert(matched.windowNumber)
            refs.append(
                WindowRef(
                    id: matched.windowNumber,
                    pid: axInfo.pid,
                    bundleID: bundleIDForPID(axInfo.pid),
                    appName: appNameForPID(axInfo.pid) ?? matched.ownerName,
                    title: axInfo.title,
                    frame: matched.bounds,
                    isMinimized: axInfo.isMinimized,
                    isFullscreen: axInfo.isFullscreen,
                    subrole: axInfo.subrole
                )
            )
        }
        return refs
    }
}
