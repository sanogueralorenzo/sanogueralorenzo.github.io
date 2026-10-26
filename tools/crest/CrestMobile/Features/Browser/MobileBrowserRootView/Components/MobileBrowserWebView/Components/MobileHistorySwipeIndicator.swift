import SwiftUI

/// The chevron in the gap a history swipe opens beside the page. It turns from
/// secondary to primary once letting go would take the step.
struct MobileHistorySwipeIndicator: View {
    let systemImage: String
    let isArmed: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(isArmed ? Color.primary : Color.secondary)
            .frame(width: CrestLayout.minimumHitTarget, height: CrestLayout.minimumHitTarget)
            .glassEffect(.regular, in: .circle)
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Following and armed") {
        HStack {
            MobileHistorySwipeIndicator(systemImage: "chevron.backward", isArmed: false)
            MobileHistorySwipeIndicator(systemImage: "chevron.backward", isArmed: true)
            MobileHistorySwipeIndicator(systemImage: "chevron.forward", isArmed: true)
        }
        .padding()
    }
#endif
