import Foundation
import Testing
import LayoutModel

@Test func deepNestingDepth20() {
    var node: Node = .panel(PanelNode(window: WindowID.stub(0)))
    for i in 1...19 {
        let next = Node.panel(PanelNode(window: WindowID.stub(i)))
        node = .split(SplitNode.equal(axis: i % 2 == 0 ? .horizontal : .vertical, children: [node, next]))
    }
    #expect(node.depth == 20)

    var ws = Workspace(root: node)
    let (normalized, _) = ws.normalized()
    ws = normalized
    #expect(ws.root.depth >= 2)
    #expect(LayoutInvariants.holds(ws))
    #expect(ws.root.tiledWindowIDs.count == 20)
}

@Test func codableRoundTripWorkspace() throws {
    var ws = Workspace.empty
    for i in 1...4 {
        (ws, _) = ws.inserting(WindowID.stub(i), at: .screenEdge(Edge.allCases[(i - 1) % 4]))
    }
    let path = ws.root.path(to: WindowID.stub(1)) ?? []
    (ws, _) = ws.inserting(WindowID.stub(10), at: .center(nodePath: path))
    (ws, _) = ws.floating(WindowID.stub(4), frame: Rect(x: 1, y: 2, width: 3, height: 4))
    ws.setState(.minimized, for: WindowID.stub(2))
    ws.camera = Camera(focusPath: path, zoom: 0.5)
    ws.excludedApps.insert("com.example.app")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(ws)
    let decoded = try JSONDecoder().decode(Workspace.self, from: data)
    #expect(decoded == ws)
}

@Test func codableRoundTripDisplayLayout() throws {
    var layout = DisplayLayout(displayUUID: "TEST-UUID")
    var ws = Workspace.empty
    (ws, _) = ws.inserting(WindowID.stub(1), at: .screenEdge(.left))
    layout.workspaces[1] = ws
    layout.saveView(3, camera: Camera(focusPath: [0], zoom: 0.8))

    let data = try JSONEncoder().encode(layout)
    let decoded = try JSONDecoder().decode(DisplayLayout.self, from: data)
    #expect(decoded == layout)
    #expect(decoded.view(3)?.zoom == 0.8)
    #expect(decoded.view(10) == nil)
}

@Test func codableRoundTripNodeVariants() throws {
    let nodes: [Node] = [
        .desktop,
        .panel(PanelNode(window: WindowID.stub(1))),
        .tabs(TabNode(windows: [WindowID.stub(1), WindowID.stub(2)], selectedIndex: 1)),
        .split(SplitNode.equal(axis: .vertical, children: [
            .panel(PanelNode(window: WindowID.stub(1))),
            .desktop,
        ])),
    ]
    for node in nodes {
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(Node.self, from: data)
        #expect(decoded == node)
    }
}
