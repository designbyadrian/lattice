import Foundation
import LayoutModel
import LayoutEngine

enum GoldenBuilders {
    static let scr = ScreenGeometry.golden
    static let cfg = LayoutConfig.default

    static func W(_ id: NodeID, min: Size? = nil, max: Size? = nil, natural: Size? = nil) -> LayoutNode {
        WindowLeaf.win(id, min: min, max: max, natural: natural)
    }

    static func deep(levels: Int = 14) -> LayoutNode {
        let names = (1...(levels + 1)).map { "W\($0)" }
        var node = W(names.last!)
        for i in stride(from: levels - 1, through: 0, by: -1) {
            let mk: ([LayoutNode], NodeID) -> LayoutNode = { kids, id in
                if i % 2 == 0 {
                    return SplitBuilder.h(kids, id: id)
                }
                return SplitBuilder.v(kids, id: id)
            }
            node = mk([W(names[i]), node], "s\(i + 1)")
        }
        return node
    }

    struct CaseInput {
        var name: String
        var root: LayoutNode
        var cfg: LayoutConfig
        var cam: EdgeRect
        var framed: NodeID?
        var prevIcons: Set<NodeID>
        var prevGroupTiles: Set<NodeID>
        var ids: Set<NodeID>?
    }

    static func allCases() -> [CaseInput] {
        Split.resetIDCounter(to: 1)
        var C: [CaseInput] = []
        let CFG = cfg

        func add(
            _ name: String,
            root: LayoutNode,
            cfg: LayoutConfig = CFG,
            cam: EdgeRect = .unit,
            framed: NodeID? = nil,
            ids: Set<NodeID>? = nil,
            prevIcons: Set<NodeID> = [],
            prevGroupTiles: Set<NodeID> = [],
            resolveCamFromFramed: Bool = false
        ) {
            var cam = cam
            var root = root
            if resolveCamFromFramed, let framed {
                let C0 = scr.contentEdges(cfg: cfg)
                let ents = LayoutSolver.solveWorld(root, cfg: cfg, homeSize: Size(width: C0.width, height: C0.height))
                if let w = ents[framed]?.slot.world {
                    cam = EdgeRect(
                        x0: (w.x0 * 1e6).rounded() / 1e6,
                        y0: (w.y0 * 1e6).rounded() / 1e6,
                        x1: (w.x1 * 1e6).rounded() / 1e6,
                        y1: (w.y1 * 1e6).rounded() / 1e6
                    )
                }
            }
            C.append(CaseInput(
                name: name,
                root: root,
                cfg: cfg,
                cam: cam,
                framed: framed,
                prevIcons: prevIcons,
                prevGroupTiles: prevGroupTiles,
                ids: ids
            ))
        }

        add("G01 single window", root: W("A"))
        add("G02 two columns", root: SplitBuilder.H(W("A"), W("B")))
        add("G03 three columns unequal", root: SplitBuilder.h([W("A"), W("B"), W("C")], ratios: [0.5, 0.25, 0.25]))
        add("G04 nested column", root: SplitBuilder.h([W("A"), SplitBuilder.V(W("B"), W("C"))], ratios: [0.6, 0.4]))
        add(
            "G05 window + desktop with float",
            root: SplitBuilder.H(
                W("A"),
                .desktop(DesktopArea(floats: [FloatWin(window: WindowLeaf(id: "F"), frac: (0.1, 0.1, 0.7, 0.6))]))
            )
        )
        add(
            "G06 tab group + window",
            root: SplitBuilder.H(
                .tabs(TabGroup(id: "g1", members: [WindowLeaf(id: "A"), WindowLeaf(id: "B")], active: 1)),
                W("C")
            )
        )
        var noshrink = CFG
        noshrink.shrinkPastAppMinimum = false
        add(
            "G07 min width honoured",
            root: SplitBuilder.H(W("A", min: Size(width: 900, height: 300)), W("B")),
            cfg: noshrink
        )
        add(
            "G08 virtual scale at home (shrink off)",
            root: SplitBuilder.h(["A", "B", "C", "D", "E"].map { W($0, min: Size(width: 400, height: 300)) }, id: "row"),
            cfg: noshrink
        )
        add(
            "G09 same tree, camera on C",
            root: SplitBuilder.h(["A", "B", "C", "D", "E"].map { W($0, min: Size(width: 400, height: 300)) }, id: "row"),
            cfg: noshrink,
            cam: EdgeRect(x0: 0.4, y0: 0, x1: 0.6, y1: 1),
            framed: "C"
        )
        add(
            "G10 frame nested node (fit check)",
            root: SplitBuilder.h([W("A"), SplitBuilder.V(W("B"), W("C"))], ratios: [0.6, 0.4]),
            cam: EdgeRect(x0: 0.6, y0: 0.5, x1: 1.0, y1: 1.0),
            framed: "C"
        )
        var odd = CFG
        odd.gapInnerX = 11
        odd.gapInnerY = 11
        odd.gapOuter = GapOuter(left: 6, top: 4, right: 8, bottom: 6)
        add("G11 odd gaps, per-side outer", root: SplitBuilder.H(W("A"), W("B"), W("C")), cfg: odd)
        add(
            "G12 pinch camera: clipped and parked",
            root: SplitBuilder.H(W("A"), W("B"), W("C"), W("D")),
            cam: EdgeRect(x0: 0.3, y0: 0, x1: 0.8, y1: 1)
        )
        add("G13 deep nesting: icon tiles", root: deep())
        add(
            "G13b same tree, camera framed on group s10",
            root: deep(),
            framed: "s10",
            resolveCamFromFramed: true
        )
        add(
            "G14 max size centred",
            root: SplitBuilder.H(W("A", max: Size(width: 500, height: 400)), W("B"))
        )
        add(
            "G15 icon tile: space below app minimum",
            root: SplitBuilder.h([W("A"), W("B", min: Size(width: 400, height: 200))], ratios: [0.8, 0.2])
        )

        // ops
        var r = SplitBuilder.H(W("A"), W("B"))
        r = TreeOps.insertAtEdge(r, targetID: "B", edge: .right, new: W("C"), cfg: CFG)
        add("G16 insert C right of B (half of the target)", root: r)

        r = SplitBuilder.H(W("A"), W("B"))
        r = TreeOps.insertAtEdge(r, targetID: "B", edge: .bottom, new: W("C"), cfg: CFG)
        add("G17 insert C below B (wrap)", root: r)

        r = SplitBuilder.h([W("A"), W("B")], ratios: [0.7, 0.3])
        r = TreeOps.insertAtEdge(r, targetID: "A", edge: .right, new: W("C"), cfg: CFG)
        r = TreeOps.remove(r, windowID: "C", cfg: CFG) ?? r
        add("G18 close undoes add (donor)", root: r)

        r = SplitBuilder.h([W("A"), W("B"), W("C")], ratios: [0.5, 0.2, 0.3])
        r = TreeOps.insertAtEdge(r, targetID: "B", edge: .right, new: W("X"), cfg: CFG)
        r = TreeOps.remove(r, windowID: "B", cfg: CFG) ?? r
        r = TreeOps.remove(r, windowID: "X", cfg: CFG) ?? r
        add("G18b donor gone: close shares with the row", root: r)

        r = SplitBuilder.h([W("A"), W("B"), W("C")], id: "row")
        let (_, ents) = LayoutSolver.solve(root: r, cfg: CFG, screen: scr)
        r = TreeOps.seamResize(r, slots: ents, splitID: "row", index: 0, delta: 100, cfg: CFG)
        add("G19 seam drag +100 pt between A and B", root: r)

        r = SplitBuilder.h(
            [W("A"), SplitBuilder.h([W("B"), W("C")], ratios: [0.25, 0.75])],
            ratios: [0.6, 0.4]
        ).normalizedOrDesktop(cfg: CFG)
        add("G20 flatten same axis", root: r)

        r = SplitBuilder.h([W("A"), W("B"), .desktop(DesktopArea())], ratios: [0.4, 0.3, 0.3])
        let (hidden, mem) = TreeOps.desktopAreaHide(r, cfg: CFG)
        r = TreeOps.desktopAreaShow(hidden, memory: mem, cfg: CFG)
        add("G21 desktop hide then show restores", root: r)

        r = TreeOps.insertAtScreenEdge(.desktop(DesktopArea()), edge: .left, new: W("A"), cfg: CFG)
        add("G22 first dock on fresh workspace", root: r)

        func many(_ n: Int) -> LayoutNode {
            var kids: [LayoutNode] = (1..<n).map { W("W\($0)", min: Size(width: 400, height: 300)) }
            kids.append(SplitBuilder.v(
                [W("X", min: Size(width: 400, height: 300)), W("Y", min: Size(width: 400, height: 300))],
                id: "grp"
            ))
            return SplitBuilder.h(kids, id: "row")
        }
        add(
            "G23 group becomes a group tile below threshold",
            root: many(14),
            cfg: noshrink,
            ids: ["grp", "X", "Y", "W1", "W13"]
        )
        add(
            "G24 hysteresis: stays a group tile",
            root: many(13),
            cfg: noshrink,
            ids: ["grp", "X", "Y", "W1"],
            prevGroupTiles: ["grp"]
        )
        add(
            "G25 hysteresis: no group tile if it wasn't one",
            root: many(13),
            cfg: noshrink,
            ids: ["grp", "X", "Y", "W1"]
        )

        // G26 pinch settle
        r = SplitBuilder.h(
            [W("A"), SplitBuilder.v([W("B"), W("C")], id: "col")],
            ratios: [0.6, 0.4],
            id: "root"
        )
        let C0 = scr.contentEdges(cfg: CFG)
        let home = Size(width: C0.width, height: C0.height)
        let settle = LayoutSolver.settleTarget(
            root: r,
            cfg: CFG,
            homeSize: home,
            cam: EdgeRect(x0: 0.5, y0: 0.45, x1: 0.95, y1: 0.95),
            pointer: Point(x: 0.8, y: 0.8)
        )
        add(
            "G26 pinch release settles on best-fitting node",
            root: r,
            framed: settle,
            resolveCamFromFramed: true
        )

        // G27 reflow
        r = SplitBuilder.h(
            [
                W("A"),
                .desktop(DesktopArea(floats: [
                    FloatWin(window: WindowLeaf(id: "F", natural: Size(width: 600, height: 400)), frac: (0.1, 0.2, 0.7, 0.7))
                ]))
            ],
            ratios: [0.3, 0.7]
        )
        let (res1, _) = LayoutSolver.solve(root: r, cfg: CFG, screen: scr)
        let old = res1["desktop"]!.frame
        r = TreeOps.insertAtEdge(r, targetID: "desktop", edge: .left, new: W("B"), cfg: CFG)
        let (res2, _) = LayoutSolver.solve(root: r, cfg: CFG, screen: scr)
        if let deskLoc = TreeOps.find(r, target: "desktop"), case .desktop(var d) = deskLoc.node {
            d.floats = TreeOps.reflowFloats(oldTile: old, newTile: res2["desktop"]!.frame, floats: d.floats, cfg: CFG)
            r = TreeOps.replace(r, oldID: d.id, with: .desktop(d))
        }
        add("G27 float reflow when the desktop area shrinks", root: r)

        add(
            "G28 docked window 99.9% on-screen stays live",
            root: SplitBuilder.H(W("A"), W("B")),
            cam: EdgeRect(x0: 0.004, y0: 0, x1: 0.504, y1: 1)
        )
        add(
            "G29 docked window 98.7% on-screen is clipped",
            root: SplitBuilder.H(W("A"), W("B")),
            cam: EdgeRect(x0: 0.01, y0: 0, x1: 0.51, y1: 1)
        )
        add(
            "G30 floating window straddling the edge is nudged in",
            root: .desktop(DesktopArea(floats: [FloatWin(window: WindowLeaf(id: "F"), frac: (0.6, 0.2, 0.95, 0.6))])),
            cam: EdgeRect(x0: 0.3, y0: 0, x1: 0.8, y1: 1)
        )
        add(
            "G31 float straddling while the desktop area is mostly off-screen",
            root: SplitBuilder.h(
                [
                    W("A"),
                    .desktop(DesktopArea(floats: [FloatWin(window: WindowLeaf(id: "F"), frac: (0.1, 0.1, 0.9, 0.6))]))
                ],
                ratios: [0.7, 0.3]
            ),
            cam: EdgeRect(x0: 0, y0: 0, x1: 0.75, y1: 1)
        )

        return C
    }
}
