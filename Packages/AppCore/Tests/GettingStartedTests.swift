import Testing
import AppCore

@Test func gettingStartedAdvancesOnlyOnMatchingEvent() {
    var model = GettingStartedModel.fresh
    #expect(model.current == .dockWindow)
    let ignored = model.handle(.zoomedIn)
    #expect(!ignored)
    #expect(model.current == .dockWindow)
    let advanced = model.handle(.docked)
    #expect(advanced)
    #expect(model.current == .resizeSeam)
}

@Test func gettingStartedSkipAndRestart() {
    var model = GettingStartedModel.fresh
    model.skip()
    #expect(!model.isVisible)
    let ignored = model.handle(.docked)
    #expect(!ignored)
    model.restart()
    #expect(model.isVisible)
    #expect(model.current == .dockWindow)
}

@Test func gettingStartedCompletesAfterLastStep() {
    var model = GettingStartedModel(current: .makeTabGroup)
    let done = model.handle(.tabGroupFormed)
    #expect(done)
    #expect(model.completed)
    #expect(!model.isVisible)
}
