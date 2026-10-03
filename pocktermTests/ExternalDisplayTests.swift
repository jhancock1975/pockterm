import Testing
import Foundation
@testable import pockterm

/// Scene stand-ins. Held for the whole test: an ObjectIdentifier of a
/// deallocated object can be handed out again.
@MainActor
private final class Scenes {
    let a = NSObject(), b = NSObject()
    var idA: ObjectIdentifier { ObjectIdentifier(a) }
    var idB: ObjectIdentifier { ObjectIdentifier(b) }
}

@Test @MainActor func noDisplayMeansNotConnected() {
    let display = ExternalDisplay()
    #expect(!display.isConnected)
}

@Test @MainActor func theFirstDisplayConnectsAndShowsTheTerminal() {
    let scenes = Scenes(), display = ExternalDisplay()
    var changes: [Bool] = []
    display.onConnectionChange = { changes.append($0) }
    display.attach(scenes.idA)
    #expect(display.isConnected)
    #expect(display.isPrimary(scenes.idA))
    #expect(changes == [true])
}

@Test @MainActor func aSecondDisplayIsIdleAndChangesNothing() {
    let scenes = Scenes(), display = ExternalDisplay()
    var changes: [Bool] = []
    display.onConnectionChange = { changes.append($0) }
    display.attach(scenes.idA)
    display.attach(scenes.idB)
    #expect(!display.isPrimary(scenes.idB))
    #expect(changes == [true])
}

@Test @MainActor func losingThePrimaryHandsTheTerminalToTheNext() {
    let scenes = Scenes(), display = ExternalDisplay()
    display.attach(scenes.idA)
    display.attach(scenes.idB)
    display.detach(scenes.idA)
    #expect(display.isConnected)
    #expect(display.isPrimary(scenes.idB))
}

@Test @MainActor func losingTheLastDisplayDisconnects() {
    let scenes = Scenes(), display = ExternalDisplay()
    var changes: [Bool] = []
    display.onConnectionChange = { changes.append($0) }
    display.attach(scenes.idA)
    display.detach(scenes.idA)
    #expect(!display.isConnected)
    #expect(changes == [true, false])
}

@Test @MainActor func repeatsAndStrangersAreIgnored() {
    let scenes = Scenes(), display = ExternalDisplay()
    var changes: [Bool] = []
    display.onConnectionChange = { changes.append($0) }
    display.attach(scenes.idA)
    display.attach(scenes.idA)
    display.detach(scenes.idB)
    #expect(display.isConnected)
    #expect(changes == [true])
}
