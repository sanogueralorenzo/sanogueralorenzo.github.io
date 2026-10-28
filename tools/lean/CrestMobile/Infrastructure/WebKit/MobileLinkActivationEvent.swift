import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

struct MobileLinkActivationEvent {

    let destinationURL: URL?
    let label: String
    let normalizedSourceRect: CGRect?
    let normalizedTouchPoint: CGPoint?

    init?(body: Any) {
        guard let values = body as? [String: Any] else { return nil }

        destinationURL = (values["href"] as? String).flatMap(URL.init(string:))
        label = values["label"] as? String ?? ""

        if let minX = Self.number(values["minX"]),
            let minY = Self.number(values["minY"]),
            let width = Self.number(values["width"]),
            let height = Self.number(values["height"])
        {
            normalizedSourceRect = CGRect(
                x: minX,
                y: minY,
                width: width,
                height: height
            )
        } else {
            normalizedSourceRect = nil
        }

        if let touchX = Self.number(values["touchX"]),
            let touchY = Self.number(values["touchY"])
        {
            normalizedTouchPoint = CGPoint(x: touchX, y: touchY)
        } else {
            normalizedTouchPoint = nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        return value as? Double
    }
}
