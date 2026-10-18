import Foundation

/// Outer gaps: left, top, right, bottom.
public struct GapOuter: Equatable, Hashable, Codable, Sendable {
    public var left: Int
    public var top: Int
    public var right: Int
    public var bottom: Int

    public init(left: Int = 10, top: Int = 10, right: Int = 10, bottom: Int = 10) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    public init(_ tuple: (Int, Int, Int, Int)) {
        self.init(left: tuple.0, top: tuple.1, right: tuple.2, bottom: tuple.3)
    }

    public var asTuple: (Int, Int, Int, Int) { (left, top, right, bottom) }
}

/// Tunables for normalize, ops, and solve (ADDENDUM-3 / refimpl `Config`).
public struct LayoutConfig: Equatable, Sendable, Codable {
    public var gapInnerX: Int
    public var gapInnerY: Int
    public var gapOuter: GapOuter
    /// `'target'` (half of the target) | `'row'`
    public var insertTakesFrom: InsertTakesFrom
    public var insertRatio: Double
    public var insertRatioMin: Double
    public var insertRatioMax: Double
    public var closeGivesTo: CloseGivesTo
    public var minRatio: Double
    public var shrinkPastAppMinimum: Bool
    public var tileFloor: Size
    public var fallbackMinSize: Size
    public var desktopMinSize: Size
    public var desktopReshowRatio: Double
    public var floatMaxFraction: Double
    public var floatMargin: Int
    public var floatCascade: Int
    public var soleFloatFillsDesktop: Bool
    public var groupTileBelow: Int
    public var groupTileAbove: Int
    public var iconTileSlack: Int
    public var tabBarHeight: Int
    public var tabBarRefSize: Size
    public var tabBarMinScale: Double
    public var tabBarHideBelow: Int
    public var liveVisibleFraction: Double
    public var floatNudgeIn: Bool

    public enum InsertTakesFrom: String, Codable, Sendable, Equatable {
        case target
        case row
    }

    public enum CloseGivesTo: String, Codable, Sendable, Equatable {
        case donor
        case row
        case neighbour
    }

    public init(
        gapInnerX: Int = 10,
        gapInnerY: Int = 10,
        gapOuter: GapOuter = GapOuter(),
        insertTakesFrom: InsertTakesFrom = .target,
        insertRatio: Double = 0.5,
        insertRatioMin: Double = 0.15,
        insertRatioMax: Double = 0.85,
        closeGivesTo: CloseGivesTo = .donor,
        minRatio: Double = 0.02,
        shrinkPastAppMinimum: Bool = true,
        tileFloor: Size = Size(width: 160, height: 100),
        fallbackMinSize: Size = Size(width: 240, height: 160),
        desktopMinSize: Size = Size(width: 240, height: 160),
        desktopReshowRatio: Double = 0.33,
        floatMaxFraction: Double = 0.7,
        floatMargin: Int = 12,
        floatCascade: Int = 24,
        soleFloatFillsDesktop: Bool = false,
        groupTileBelow: Int = 100,
        groupTileAbove: Int = 124,
        iconTileSlack: Int = 2,
        tabBarHeight: Int = 28,
        tabBarRefSize: Size = Size(width: 400, height: 280),
        tabBarMinScale: Double = 0.35,
        tabBarHideBelow: Int = 12,
        liveVisibleFraction: Double = 0.99,
        floatNudgeIn: Bool = true
    ) {
        self.gapInnerX = gapInnerX
        self.gapInnerY = gapInnerY
        self.gapOuter = gapOuter
        self.insertTakesFrom = insertTakesFrom
        self.insertRatio = insertRatio
        self.insertRatioMin = insertRatioMin
        self.insertRatioMax = insertRatioMax
        self.closeGivesTo = closeGivesTo
        self.minRatio = minRatio
        self.shrinkPastAppMinimum = shrinkPastAppMinimum
        self.tileFloor = tileFloor
        self.fallbackMinSize = fallbackMinSize
        self.desktopMinSize = desktopMinSize
        self.desktopReshowRatio = desktopReshowRatio
        self.floatMaxFraction = floatMaxFraction
        self.floatMargin = floatMargin
        self.floatCascade = floatCascade
        self.soleFloatFillsDesktop = soleFloatFillsDesktop
        self.groupTileBelow = groupTileBelow
        self.groupTileAbove = groupTileAbove
        self.iconTileSlack = iconTileSlack
        self.tabBarHeight = tabBarHeight
        self.tabBarRefSize = tabBarRefSize
        self.tabBarMinScale = tabBarMinScale
        self.tabBarHideBelow = tabBarHideBelow
        self.liveVisibleFraction = liveVisibleFraction
        self.floatNudgeIn = floatNudgeIn
    }

    /// Convenience matching Python tuple form.
    public init(
        gapInnerX: Int,
        gapInnerY: Int,
        gapOuter: (Int, Int, Int, Int),
        insertTakesFrom: InsertTakesFrom = .target,
        insertRatio: Double = 0.5,
        insertRatioMin: Double = 0.15,
        insertRatioMax: Double = 0.85,
        closeGivesTo: CloseGivesTo = .donor,
        minRatio: Double = 0.02,
        shrinkPastAppMinimum: Bool = true,
        tileFloor: (Double, Double) = (160, 100),
        fallbackMinSize: (Double, Double) = (240, 160),
        desktopMinSize: (Double, Double) = (240, 160),
        desktopReshowRatio: Double = 0.33,
        floatMaxFraction: Double = 0.7,
        floatMargin: Int = 12,
        floatCascade: Int = 24,
        soleFloatFillsDesktop: Bool = false,
        groupTileBelow: Int = 100,
        groupTileAbove: Int = 124,
        iconTileSlack: Int = 2,
        tabBarHeight: Int = 28,
        tabBarRefSize: (Double, Double) = (400, 280),
        tabBarMinScale: Double = 0.35,
        tabBarHideBelow: Int = 12,
        liveVisibleFraction: Double = 0.99,
        floatNudgeIn: Bool = true
    ) {
        self.init(
            gapInnerX: gapInnerX,
            gapInnerY: gapInnerY,
            gapOuter: GapOuter(gapOuter),
            insertTakesFrom: insertTakesFrom,
            insertRatio: insertRatio,
            insertRatioMin: insertRatioMin,
            insertRatioMax: insertRatioMax,
            closeGivesTo: closeGivesTo,
            minRatio: minRatio,
            shrinkPastAppMinimum: shrinkPastAppMinimum,
            tileFloor: Size(width: tileFloor.0, height: tileFloor.1),
            fallbackMinSize: Size(width: fallbackMinSize.0, height: fallbackMinSize.1),
            desktopMinSize: Size(width: desktopMinSize.0, height: desktopMinSize.1),
            desktopReshowRatio: desktopReshowRatio,
            floatMaxFraction: floatMaxFraction,
            floatMargin: floatMargin,
            floatCascade: floatCascade,
            soleFloatFillsDesktop: soleFloatFillsDesktop,
            groupTileBelow: groupTileBelow,
            groupTileAbove: groupTileAbove,
            iconTileSlack: iconTileSlack,
            tabBarHeight: tabBarHeight,
            tabBarRefSize: Size(width: tabBarRefSize.0, height: tabBarRefSize.1),
            tabBarMinScale: tabBarMinScale,
            tabBarHideBelow: tabBarHideBelow,
            liveVisibleFraction: liveVisibleFraction,
            floatNudgeIn: floatNudgeIn
        )
    }

    public static let `default` = LayoutConfig()
}
