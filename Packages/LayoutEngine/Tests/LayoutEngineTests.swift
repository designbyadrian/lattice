import Testing
import Foundation
import LayoutEngine
import LayoutModel

@Test func layoutEngineModuleName() {
    #expect(LayoutEngineModule.name == "LayoutEngine")
}

// MARK: - Goldens

private struct GoldenExpect: Decodable {
    var `class`: String
    var frame: [Double]
    var real: [Double]?
}

private struct GoldenCase: Decodable {
    var name: String
    var camera: [Double]
    var expect: [String: GoldenExpect]
}

private func loadGoldens() throws -> [GoldenCase] {
    let url = Bundle.module.url(forResource: "goldens", withExtension: "json", subdirectory: "Fixtures")
        ?? Bundle.module.url(forResource: "goldens", withExtension: "json")
    let data = try Data(contentsOf: url!)
    return try JSONDecoder().decode([GoldenCase].self, from: data)
}

private func rectList(_ r: Rect) -> [Double] {
    [r.x, r.y, r.width, r.height]
}

@Test func goldensMatchRefimpl() throws {
    let want = try loadGoldens()
    let got = GoldenBuilders.allCases()
    #expect(got.count == want.count)

    var passed = 0
    for (input, golden) in zip(got, want) {
        #expect(input.name == golden.name, "case order mismatch: \(input.name) vs \(golden.name)")
        let (res, _) = LayoutSolver.solve(
            root: input.root,
            cfg: input.cfg,
            screen: GoldenBuilders.scr,
            camera: input.cam,
            framed: input.framed,
            prevIcons: input.prevIcons,
            prevGroupTiles: input.prevGroupTiles
        )
        var filtered = res
        if let ids = input.ids {
            filtered = res.filter { ids.contains($0.key) }
        }
        // Compare against golden expect keys only (goldens may omit some structural ids).
        for (id, exp) in golden.expect {
            guard let p = filtered[id] ?? res[id] else {
                Issue.record("\(golden.name): missing placement \(id)")
                continue
            }
            #expect(p.cls == exp.class, "\(golden.name) \(id) class \(p.cls) != \(exp.class)")
            #expect(rectList(p.frame) == exp.frame, "\(golden.name) \(id) frame \(rectList(p.frame)) != \(exp.frame)")
            let gotReal = p.real.map(rectList)
            #expect(gotReal == exp.real, "\(golden.name) \(id) real \(String(describing: gotReal)) != \(String(describing: exp.real))")
        }
        passed += 1
    }
    #expect(passed == want.count)
}

// MARK: - Property tests (from refimpl/test_refimpl.py)

@Test func shareSpaceConservesTotal() {
    var rng = SeededRNG(seed: 1)
    for _ in 0..<2000 {
        let n = rng.int(1...6)
        var r = (0..<n).map { _ in rng.double(0.01...1) }
        let s = r.reduce(0, +)
        r = r.map { $0 / s }
        let m = (0..<n).map { _ in rng.double(0...300) }
        let M = (0..<n).map { i in
            rng.bool() ? LayoutMath.inf : m[i] + rng.double(0...500)
        }
        let T = m.reduce(0, +) + rng.double(0...1500)
        let p = ShareSpace.share(total: T, ratios: r, mins: m, maxes: M)
        #expect(abs(p.reduce(0, +) - T) < 1e-6)
        for i in 0..<n {
            #expect(p[i] >= m[i] - 1e-6)
            if M.reduce(0, +) >= T {
                #expect(p[i] <= M[i] + 1e-6)
            }
        }
    }
}

@Test func fitCheckEveryNode() {
    var rng = SeededRNG(seed: 3)
    let scr = ScreenGeometry.golden
    let cfg = LayoutConfig.default
    for _ in 0..<150 {
        let root = normalize(randTree(&rng), cfg: cfg)
        let C = scr.contentEdges(cfg: cfg)
        let ents = LayoutSolver.worldEntries(root, cfg: cfg, homeSize: Size(width: C.width, height: C.height))
        for (k, slot) in ents {
            let t = LayoutSolver.tileOf(slot.world, cam: slot.world, C: C, cfg: cfg)
            #expect(rectList(t) == [10, 35, 1420, 855], "fit \(k) \(rectList(t))")
        }
    }
}

@Test func straddleRule() {
    let root = SplitBuilder.H(WindowLeaf.win("A"), WindowLeaf.win("B"))
    let scr = ScreenGeometry.golden
    let cfg = LayoutConfig.default
    let cases: [(EdgeRect, String)] = [
        (EdgeRect(x0: 0.004, y0: 0, x1: 0.504, y1: 1), "live"),
        (EdgeRect(x0: 0.01, y0: 0, x1: 0.51, y1: 1), "clipped"),
    ]
    for (cam, want) in cases {
        let (res, _) = LayoutSolver.solve(root: root, cfg: cfg, screen: scr, camera: cam)
        #expect(res["A"]?.cls == want)
    }
}

@Test func insertTakesHalfOfTargetProperty() {
    var rng = SeededRNG(seed: 6)
    let cfg = LayoutConfig.default
    for _ in 0..<200 {
        let root = normalize(randTree(&rng), cfg: cfg)
        let leaves = leafWindows(root)
        guard let tgt = leaves.randomElement(using: &rng) else { continue }
        guard let loc = TreeOps.find(root, target: tgt.id),
              case .split(let p0) = loc.parent,
              let i0 = loc.index else { continue }
        let before = p0.ratios[i0]
        let axis: Axis = rng.bool() ? .horizontal : .vertical
        let edge: Edge = axis == .horizontal ? (rng.bool() ? .left : .right) : (rng.bool() ? .top : .bottom)
        let r2 = TreeOps.insertAtEdge(root, targetID: tgt.id, edge: edge, new: WindowLeaf.win("new"), cfg: cfg)
        guard let locN = TreeOps.find(r2, target: "new"),
              let locT = TreeOps.find(r2, target: tgt.id),
              case .split(let pn) = locN.parent,
              locN.parent?.id == locT.parent?.id,
              p0.axis == axis,
              before * 0.5 >= cfg.minRatio,
              let iN = locN.index, let iT = locT.index else { continue }
        #expect(abs(pn.ratios[iN] - before * 0.5) < 1e-9)
        #expect(abs(pn.ratios[iT] - before * 0.5) < 1e-9)
    }
}

@Test func seamOnlyTwoChange() {
    var root = SplitBuilder.h(
        [WindowLeaf.win("a"), SplitBuilder.V(WindowLeaf.win("b"), WindowLeaf.win("c")), WindowLeaf.win("d")],
        id: "row"
    )
    let scr = ScreenGeometry.golden
    let cfg = LayoutConfig.default
    let (res, ents) = LayoutSolver.solve(root: root, cfg: cfg, screen: scr)
    root = TreeOps.seamResize(root, slots: ents, splitID: "row", index: 1, delta: -120, cfg: cfg)
    let (res2, _) = LayoutSolver.solve(root: root, cfg: cfg, screen: scr)
    let changed = Set(res.keys.filter { res[$0]!.frame != res2[$0]?.frame })
    #expect(changed == Set(["b", "c", "d"]))
    #expect(res2["d"]!.frame.maxX == res["d"]!.frame.maxX)
}

// MARK: - Helpers

private func normalize(_ n: LayoutNode, cfg: LayoutConfig) -> LayoutNode {
    n.normalizedOrDesktop(cfg: cfg)
}

private func leafWindows(_ n: LayoutNode) -> [WindowLeaf] {
    switch n {
    case .window(let w): return [w]
    case .split(let s): return s.children.flatMap(leafWindows)
    case .tabs(let t): return t.members
    case .desktop: return []
    }
}

private func randTree(_ rng: inout SeededRNG, depth: Int = 0) -> LayoutNode {
    if depth > 4 || (depth > 0 && rng.double(0...1) < 0.35) {
        return WindowLeaf.win("w\(rng.nextTag())")
    }
    let n = rng.int(2...4)
    let kids = (0..<n).map { _ in randTree(&rng, depth: depth + 1) }
    var r = (0..<n).map { _ in rng.double(0.5...2) }
    let s = r.reduce(0, +)
    r = r.map { $0 / s }
    let axis: Axis = rng.bool() ? .horizontal : .vertical
    return .split(Split(axis: axis, children: kids, ratios: r))
}

/// Tiny deterministic RNG for property tests.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    private var tag: Int = 0

    init(seed: UInt64) { state = seed == 0 ? 0xdeadbeef : seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }

    mutating func nextTag() -> Int {
        tag += 1
        return tag
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        let u = next() % UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(u)
    }

    mutating func double(_ range: ClosedRange<Double>) -> Double {
        let x = Double(next() % 10_000_000) / 10_000_000
        return range.lowerBound + x * (range.upperBound - range.lowerBound)
    }

    mutating func bool() -> Bool { next() % 2 == 0 }
}

extension Array {
    func randomElement(using rng: inout SeededRNG) -> Element? {
        guard !isEmpty else { return nil }
        return self[rng.int(0...(count - 1))]
    }
}
