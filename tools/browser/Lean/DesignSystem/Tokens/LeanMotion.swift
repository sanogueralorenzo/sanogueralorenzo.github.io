import SwiftUI

enum LeanMotion {
    static var surface: Animation { .easeInOut(duration: 0.12) }
    // Crest's motion roles keep chrome, collection changes and lifts distinct.
    static var floatingPane: Animation { .smooth(duration: 0.24) }
    static var collection: Animation { .snappy(duration: 0.22) }
    static var dragSource: Animation { .snappy(duration: 0.20) }
    static var dragPreview: Animation { .smooth(duration: 0.18) }
    static var disclosure: Animation { .snappy(duration: 0.20) }
}
