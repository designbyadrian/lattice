import Foundation

public enum InsertTakesFrom: String, Sendable, Equatable {
    case target
    case row
}

public enum CloseGivesTo: String, Sendable, Equatable {
    case donor
    case row
    case neighbour
}

/// `[layout]` Lattice extension (ADDENDUM-3 §9).
public struct LayoutGeometryConfig: Sendable, Equatable {
    public var insertTakesFrom: InsertTakesFrom
    public var insertRatio: Double
    public var closeGivesTo: CloseGivesTo
    public var liveVisibleFraction: Double
    public var minRatio: Double
    public var shrinkPastAppMinimum: Bool
    public var tileFloor: (width: Double, height: Double)
    public var fallbackMinSize: (width: Double, height: Double)
    public var dropEdgeFraction: Double
    public var screenEdgeBand: Int

    public init(
        insertTakesFrom: InsertTakesFrom = .target,
        insertRatio: Double = 0.5,
        closeGivesTo: CloseGivesTo = .donor,
        liveVisibleFraction: Double = 0.99,
        minRatio: Double = 0.02,
        shrinkPastAppMinimum: Bool = true,
        tileFloor: (width: Double, height: Double) = (160, 100),
        fallbackMinSize: (width: Double, height: Double) = (240, 160),
        dropEdgeFraction: Double = 0.25,
        screenEdgeBand: Int = 8
    ) {
        self.insertTakesFrom = insertTakesFrom
        self.insertRatio = insertRatio
        self.closeGivesTo = closeGivesTo
        self.liveVisibleFraction = liveVisibleFraction
        self.minRatio = minRatio
        self.shrinkPastAppMinimum = shrinkPastAppMinimum
        self.tileFloor = tileFloor
        self.fallbackMinSize = fallbackMinSize
        self.dropEdgeFraction = dropEdgeFraction
        self.screenEdgeBand = screenEdgeBand
    }

    public static let `default` = LayoutGeometryConfig()

    public static func == (lhs: LayoutGeometryConfig, rhs: LayoutGeometryConfig) -> Bool {
        lhs.insertTakesFrom == rhs.insertTakesFrom
            && lhs.insertRatio == rhs.insertRatio
            && lhs.closeGivesTo == rhs.closeGivesTo
            && lhs.liveVisibleFraction == rhs.liveVisibleFraction
            && lhs.minRatio == rhs.minRatio
            && lhs.shrinkPastAppMinimum == rhs.shrinkPastAppMinimum
            && lhs.tileFloor.width == rhs.tileFloor.width
            && lhs.tileFloor.height == rhs.tileFloor.height
            && lhs.fallbackMinSize.width == rhs.fallbackMinSize.width
            && lhs.fallbackMinSize.height == rhs.fallbackMinSize.height
            && lhs.dropEdgeFraction == rhs.dropEdgeFraction
            && lhs.screenEdgeBand == rhs.screenEdgeBand
    }
}

/// `[zoom]` Lattice extension (ADDENDUM-3 §9).
public struct ZoomConfig: Sendable, Equatable {
    public var iconTileSlack: Int
    public var groupTileBelow: Int
    public var groupTileAbove: Int
    public var stillTimeoutMs: Int

    public init(
        iconTileSlack: Int = 2,
        groupTileBelow: Int = 100,
        groupTileAbove: Int = 124,
        stillTimeoutMs: Int = 600
    ) {
        self.iconTileSlack = iconTileSlack
        self.groupTileBelow = groupTileBelow
        self.groupTileAbove = groupTileAbove
        self.stillTimeoutMs = stillTimeoutMs
    }

    public static let `default` = ZoomConfig()
}

/// `[tabs]` Lattice extension (ADDENDUM-3 §9).
public struct TabsConfig: Sendable, Equatable {
    public var tabBarHeight: Int
    public var tabBarRefSize: (width: Double, height: Double)
    public var tabBarMinScale: Double
    public var tabBarHideBelow: Int

    public init(
        tabBarHeight: Int = 28,
        tabBarRefSize: (width: Double, height: Double) = (400, 280),
        tabBarMinScale: Double = 0.35,
        tabBarHideBelow: Int = 12
    ) {
        self.tabBarHeight = tabBarHeight
        self.tabBarRefSize = tabBarRefSize
        self.tabBarMinScale = tabBarMinScale
        self.tabBarHideBelow = tabBarHideBelow
    }

    public static let `default` = TabsConfig()

    public static func == (lhs: TabsConfig, rhs: TabsConfig) -> Bool {
        lhs.tabBarHeight == rhs.tabBarHeight
            && lhs.tabBarRefSize.width == rhs.tabBarRefSize.width
            && lhs.tabBarRefSize.height == rhs.tabBarRefSize.height
            && lhs.tabBarMinScale == rhs.tabBarMinScale
            && lhs.tabBarHideBelow == rhs.tabBarHideBelow
    }
}

/// `[desktop-area]` Lattice extension (ADDENDUM-3 §9).
public struct DesktopAreaConfig: Sendable, Equatable {
    public var minSize: (width: Double, height: Double)
    public var reshowRatio: Double
    public var dropEdgeFraction: Double
    public var dropEdgeMax: Int
    public var floatMaxFraction: Double
    public var floatMargin: Int
    public var floatCascade: Int
    public var soleFloatFills: Bool
    public var floatNudgeIn: Bool

    public init(
        minSize: (width: Double, height: Double) = (240, 160),
        reshowRatio: Double = 0.33,
        dropEdgeFraction: Double = 0.18,
        dropEdgeMax: Int = 60,
        floatMaxFraction: Double = 0.7,
        floatMargin: Int = 12,
        floatCascade: Int = 24,
        soleFloatFills: Bool = false,
        floatNudgeIn: Bool = true
    ) {
        self.minSize = minSize
        self.reshowRatio = reshowRatio
        self.dropEdgeFraction = dropEdgeFraction
        self.dropEdgeMax = dropEdgeMax
        self.floatMaxFraction = floatMaxFraction
        self.floatMargin = floatMargin
        self.floatCascade = floatCascade
        self.soleFloatFills = soleFloatFills
        self.floatNudgeIn = floatNudgeIn
    }

    public static let `default` = DesktopAreaConfig()

    public static func == (lhs: DesktopAreaConfig, rhs: DesktopAreaConfig) -> Bool {
        lhs.minSize.width == rhs.minSize.width
            && lhs.minSize.height == rhs.minSize.height
            && lhs.reshowRatio == rhs.reshowRatio
            && lhs.dropEdgeFraction == rhs.dropEdgeFraction
            && lhs.dropEdgeMax == rhs.dropEdgeMax
            && lhs.floatMaxFraction == rhs.floatMaxFraction
            && lhs.floatMargin == rhs.floatMargin
            && lhs.floatCascade == rhs.floatCascade
            && lhs.soleFloatFills == rhs.soleFloatFills
            && lhs.floatNudgeIn == rhs.floatNudgeIn
    }
}

/// `[window-sizing]` Lattice extension (ADDENDUM-3 §9).
public struct WindowSizingConfig: Sendable, Equatable {
    public var axRetries: Int
    public var axReadbackDelayMs: Int
    public var axRetryIntervalMs: Int
    public var axRetryWindowMs: Int
    public var axSizeTolerance: Int
    public var axMaxResolves: Int
    public var learnMinimums: Bool

    public init(
        axRetries: Int = 3,
        axReadbackDelayMs: Int = 120,
        axRetryIntervalMs: Int = 200,
        axRetryWindowMs: Int = 2000,
        axSizeTolerance: Int = 16,
        axMaxResolves: Int = 3,
        learnMinimums: Bool = true
    ) {
        self.axRetries = axRetries
        self.axReadbackDelayMs = axReadbackDelayMs
        self.axRetryIntervalMs = axRetryIntervalMs
        self.axRetryWindowMs = axRetryWindowMs
        self.axSizeTolerance = axSizeTolerance
        self.axMaxResolves = axMaxResolves
        self.learnMinimums = learnMinimums
    }

    public static let `default` = WindowSizingConfig()
}
