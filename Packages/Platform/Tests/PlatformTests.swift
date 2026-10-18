import Testing
import Platform

@Test func platformModuleName() {
    #expect(PlatformModule.name == "Platform")
}

@Test func rectCodable() {
    let r = CGRectCodable(x: 0, y: 0, width: 100, height: 50)
    #expect(r.maxX == 100)
    #expect(r.maxY == 50)
    #expect(r.isApproximatelyEqual(to: CGRectCodable(x: 1, y: 1, width: 100, height: 50), tolerance: 2))
}
