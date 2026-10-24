import AppKit
import XCTest

/// Sends fixture input through the application queue and owns its terminal release.
@MainActor
final class BrowserNativeMouseInput {
    private static let eventSettlingInterval: TimeInterval = 0.03

    private let window: NSWindow
    private var eventNumber = 0
    private var mouseIsDown = false
    private var lastLocation = CGPoint.zero

    init(window: NSWindow) {
        self.window = window
    }

    func send(
        _ type: NSEvent.EventType, at location: CGPoint,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        eventNumber += 1
        let height = window.contentView?.bounds.height ?? 0
        guard
            let event = NSEvent.mouseEvent(
                with: type,
                location: CGPoint(x: location.x, y: height - location.y),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: eventNumber,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            )
        else {
            XCTFail("The native mouse event could not be created.", file: file, line: line)
            return
        }
        // Dequeue before dispatch so AppKit's currentEvent and gesture lifecycle
        // see the same input as local monitors and the destination window.
        NSApplication.shared.postEvent(event, atStart: true)
        guard
            let queued = NSApplication.shared.nextEvent(
                matching: NSEvent.EventTypeMask(rawValue: 1 << type.rawValue),
                until: .distantPast, inMode: .default, dequeue: true
            )
        else {
            XCTFail("The native mouse event was not queued.", file: file, line: line)
            return
        }
        lastLocation = location
        if type == .leftMouseDown { mouseIsDown = true }
        if type == .leftMouseUp { mouseIsDown = false }
        NSApplication.shared.sendEvent(queued)
        RunLoop.current.run(until: Date().addingTimeInterval(Self.eventSettlingInterval))
    }

    func close() {
        if mouseIsDown { send(.leftMouseUp, at: lastLocation) }
        window.close()
    }
}
