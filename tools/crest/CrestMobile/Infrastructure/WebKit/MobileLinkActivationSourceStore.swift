import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

struct MobileLinkActivationSourceStore {
    private struct Entry {
        let destinationURL: URL
        let sourcePresentation: BrowserPeekSourcePresentation
        let uptime: TimeInterval
    }

    let maximumAge: TimeInterval
    private var entry: Entry?

    init(maximumAge: TimeInterval = 1.25) {
        precondition(maximumAge > 0)
        self.maximumAge = maximumAge
    }

    mutating func record(
        destinationURL: URL,
        sourcePresentation: BrowserPeekSourcePresentation,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        entry = Entry(
            destinationURL: destinationURL,
            sourcePresentation: sourcePresentation,
            uptime: uptime
        )
    }

    mutating func consume(
        destinationURL: URL?,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> BrowserPeekSourcePresentation? {
        guard let entry else { return nil }
        self.entry = nil
        let age = uptime - entry.uptime
        guard age >= 0,
            age <= maximumAge,
            destinationURL?.absoluteString == entry.destinationURL.absoluteString
        else {
            return nil
        }
        return entry.sourcePresentation
    }

    mutating func removeAll() {
        entry = nil
    }
}
