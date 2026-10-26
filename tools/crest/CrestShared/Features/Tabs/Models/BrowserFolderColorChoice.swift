import SwiftUI

struct BrowserFolderColorChoice: Identifiable, Equatable, Sendable {
    let title: String
    let value: BrandColor

    var id: BrandColor { value }
}
