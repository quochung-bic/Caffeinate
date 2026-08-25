import Testing
@testable import CaffeinateKit

@Suite("TriggerEngine")
@MainActor
struct TriggerEngineTests {

    @Test("start starts every child trigger, stop stops them all")
    func startsAndStopsAllTriggers() {
        let a = FakeTrigger()
        let b = FakeTrigger()
        let engine = TriggerEngine(triggers: [a, b])

        engine.start()
        #expect(a.started && b.started)

        engine.stop()
        #expect(a.stopped && b.stopped)
    }

    @Test("a trigger switching on emits triggerFired")
    func emitsFiredEvent() {
        let trigger = FakeTrigger()
        let engine = TriggerEngine(triggers: [trigger])
        var events: [CaffeineEvent] = []
        engine.onEvent = { events.append($0) }
        engine.start()

        trigger.fire(.app("Xcode"), active: true)

        #expect(events == [.triggerFired(.app("Xcode"))])
    }

    @Test("a trigger switching off emits triggerCleared")
    func emitsClearedEvent() {
        let trigger = FakeTrigger()
        let engine = TriggerEngine(triggers: [trigger])
        var events: [CaffeineEvent] = []
        engine.onEvent = { events.append($0) }
        engine.start()

        trigger.fire(.charging, active: true)
        trigger.fire(.charging, active: false)

        #expect(events == [.triggerFired(.charging), .triggerCleared(.charging)])
    }

    @Test("several triggers fire independently and are never conflated")
    func multipleTriggersStayIndependent() {
        let apps = FakeTrigger()
        let power = FakeTrigger()
        let engine = TriggerEngine(triggers: [apps, power])
        var events: [CaffeineEvent] = []
        engine.onEvent = { events.append($0) }
        engine.start()

        apps.fire(.app("Docker"), active: true)
        power.fire(.charging, active: true)
        apps.fire(.app("Docker"), active: false)

        #expect(events == [
            .triggerFired(.app("Docker")),
            .triggerFired(.charging),
            .triggerCleared(.app("Docker")),
        ])
    }

    @Test("after stop, nothing is emitted any more")
    func silentAfterStop() {
        let trigger = FakeTrigger()
        let engine = TriggerEngine(triggers: [trigger])
        var events: [CaffeineEvent] = []
        engine.onEvent = { events.append($0) }
        engine.start()
        engine.stop()

        trigger.fire(.charging, active: true)

        #expect(events.isEmpty)
    }
}
