import Testing
import LayoutModel

@Test func geometryBasics() {
    let rect = Rect(x: 10, y: 20, width: 100, height: 50)
    #expect(rect.minX == 10)
    #expect(rect.maxX == 110)
    #expect(rect.midY == 45)
    #expect(Edge.left.splitAxis == .horizontal)
    #expect(Edge.top.placesNewFirst)
    #expect(!Edge.right.placesNewFirst)
}
