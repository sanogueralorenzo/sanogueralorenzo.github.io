import SwiftUI

struct BrowserSpaceBrowsingPickerValueLayout: Equatable {
    let minimumLeadingGap: CGFloat
    let disclosureSpacing: CGFloat
    let verticalPadding: CGFloat

    static let touch = Self(
        minimumLeadingGap: 16,
        disclosureSpacing: 8,
        verticalPadding: 5
    )
}
