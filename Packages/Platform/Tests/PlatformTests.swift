import Testing
import Platform

@Test func rectCodable() {
    let r = CGRectCodable(x: 0, y: 0, width: 100, height: 50)
    #expect(r.maxX == 100)
    #expect(r.maxY == 50)
}
