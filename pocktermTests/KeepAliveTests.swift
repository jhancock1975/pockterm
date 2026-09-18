import Testing
@testable import pockterm

@Test @MainActor func optionsStartWithOffThenAscend() {
    let secs = KeepAlive.options.map(\.seconds)
    #expect(secs == [0, 300, 900, 1800, 3600])
    #expect(KeepAlive.options.first?.label == "Off")
}

@Test @MainActor func labelForKnownAndUnknown() {
    #expect(KeepAlive.label(for: 0) == "Off")
    #expect(KeepAlive.label(for: 1800) == "30 min")
    #expect(KeepAlive.label(for: 12345) == "Off")   // unknown → Off
}

@Test @MainActor func idleDisconnectOffNeverFires() {
    #expect(KeepAlive.shouldIdleDisconnect(idleSeconds: 999999, holdSeconds: 0) == false)
}

@Test @MainActor func idleDisconnectFiresAtOrAboveHold() {
    #expect(KeepAlive.shouldIdleDisconnect(idleSeconds: 1799, holdSeconds: 1800) == false)
    #expect(KeepAlive.shouldIdleDisconnect(idleSeconds: 1800, holdSeconds: 1800) == true)
    #expect(KeepAlive.shouldIdleDisconnect(idleSeconds: 5000, holdSeconds: 1800) == true)
}
