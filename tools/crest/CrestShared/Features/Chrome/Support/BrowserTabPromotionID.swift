import Foundation

enum BrowserTabPromotionID {
    static func value(for tabID: UUID) -> String {
        "crest-tab-promotion-\(tabID)"
    }
}
