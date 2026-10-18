import Testing
import LayoutModel

enum RandomOp: CaseIterable {
    case insertScreen
    case insertEdge
    case insertCenter
    case remove
    case resize
    case tab
    case untab
    case float
    case dock
    case floatAll
    case swap
    case move
    case normalize
}

struct LCG: Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }
    mutating func int(below upper: Int) -> Int {
        guard upper > 0 else { return 0 }
        return Int(next() % UInt64(upper))
    }
    mutating func pick<T>(_ items: [T]) -> T {
        items[int(below: items.count)]
    }
    mutating func double() -> Double {
        Double(next() % 10_000) / 10_000.0
    }
}

@Test func randomOpSequencesKeepInvariants() {
    for seed in UInt64(1)...UInt64(40) {
        var rng = LCG(seed: seed)
        var ws = Workspace.empty
        var nextTag = 1

        for _ in 0..<80 {
            let op = RandomOp.allCases[rng.int(below: RandomOp.allCases.count)]
            switch op {
            case .insertScreen:
                let w = WindowID.stub(nextTag)
                nextTag += 1
                let edge = Edge.allCases[rng.int(below: 4)]
                (ws, _) = ws.inserting(w, at: .screenEdge(edge))
            case .insertEdge:
                let paths = ws.root.allPaths()
                let w = WindowID.stub(nextTag)
                nextTag += 1
                let path = rng.pick(paths)
                let edge = Edge.allCases[rng.int(below: 4)]
                (ws, _) = ws.inserting(w, at: .edge(nodePath: path, edge: edge))
            case .insertCenter:
                let paths = ws.root.allPaths()
                let w = WindowID.stub(nextTag)
                nextTag += 1
                (ws, _) = ws.inserting(w, at: .center(nodePath: rng.pick(paths)))
            case .remove:
                let ids = ws.allWindowIDs
                if let id = ids.randomElement(using: &rng) {
                    (ws, _) = ws.removing(id)
                }
            case .resize:
                if case .split(let split) = ws.root, split.children.count >= 2 {
                    let divider = rng.int(below: split.children.count - 1)
                    let delta = (rng.double() - 0.5) * 0.2
                    (ws, _) = ws.resizing(path: [], dividerIndex: divider, delta: delta)
                }
            case .tab:
                let tiled = ws.root.tiledWindowIDs
                if tiled.count >= 2 {
                    let a = tiled[rng.int(below: tiled.count)]
                    var b = tiled[rng.int(below: tiled.count)]
                    if a == b { b = tiled[(tiled.firstIndex(of: a)! + 1) % tiled.count] }
                    (ws, _) = ws.tabbing(a, onto: b)
                }
            case .untab:
                for id in ws.root.tiledWindowIDs {
                    if let path = ws.root.path(to: id), case .tabs = ws.root.node(at: path) {
                        (ws, _) = ws.untabbing(id)
                        break
                    }
                }
            case .float:
                if let id = ws.root.tiledWindowIDs.randomElement(using: &rng) {
                    (ws, _) = ws.floating(id, frame: Rect(x: 0, y: 0, width: 200, height: 200))
                }
            case .dock:
                if let floater = ws.floating.randomElement(using: &rng) {
                    let edge = Edge.allCases[rng.int(below: 4)]
                    (ws, _) = ws.docking(floater.id, at: .screenEdge(edge))
                }
            case .floatAll:
                (ws, _) = ws.floatingAll()
            case .swap:
                let ids = ws.allWindowIDs
                if ids.count >= 2 {
                    let a = ids[rng.int(below: ids.count)]
                    let b = ids[rng.int(below: ids.count)]
                    (ws, _) = ws.swapping(a, with: b)
                }
            case .move:
                if let id = ws.allWindowIDs.randomElement(using: &rng) {
                    let edge = Edge.allCases[rng.int(below: 4)]
                    (ws, _) = ws.moving(id, to: .screenEdge(edge))
                }
            case .normalize:
                (ws, _) = ws.normalized()
            }

            (ws, _) = ws.normalized()
            let violations = LayoutInvariants.check(ws)
            #expect(violations.isEmpty, "seed \(seed): \(violations)")
        }
    }
}

private extension Array {
    func randomElement(using rng: inout LCG) -> Element? {
        guard !isEmpty else { return nil }
        return self[rng.int(below: count)]
    }
}
