import SwiftUI

struct BrowserSourceImportTabRow: View {
    let review: BrowserImportSpaceReview
    let tab: TabStateModel
    let overflowTabIDs: Set<UUID>
    let duplicateTabIDs: Set<UUID>
    let duplicateDestinationName: String?
    let setIncluded: (UUID, Bool) -> Void
    let setPlacement: (UUID, TabPlacement) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                setIncluded(tab.id, !included)
            } label: {
                TabFaviconView(
                    subject: BrowserTabFaviconSubject(tab: tab, image: nil),
                    profileID: review.sourceSpace.profileID,
                    size: 18
                )
                Text(tab.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if overflows {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                } else if !included {
                    Image(systemName: duplicate ? "equal.circle.fill" : "minus.circle.fill")
                        .foregroundStyle(
                            duplicate ? BrowserOnboardingPalette.match : Color.secondary
                        )
                }
            }
            .buttonStyle(.plain)
            .opacity(duplicate || included ? 1 : 0.4)

            BrowserSourceImportTabPlacementMenu(
                tab: tab,
                setPlacement: setPlacement
            )
        }
        .padding(.leading, 17)
        .padding(.trailing, 9)
        .frame(height: 40)
        .background(
            duplicate
                ? BrowserOnboardingPalette.match.opacity(0.16)
                : overflows ? Color.red.opacity(0.18) : .clear,
            in: .rect(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            if duplicate {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        BrowserOnboardingPalette.match.opacity(0.52),
                        lineWidth: 0.75
                    )
            }
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.title)
        .accessibilityValue(accessibilityValue)
    }

    private var included: Bool { review.includedTabIDs.contains(tab.id) }
    private var overflows: Bool { overflowTabIDs.contains(tab.id) && included }
    private var duplicate: Bool { duplicateTabIDs.contains(tab.id) }

    private var accessibilityValue: String {
        if overflows {
            return "Included, pinned capacity full, moves to Imported Pinned Tabs"
        }
        if !included, duplicate {
            return "Already in \(duplicateDestinationName ?? "destination"), not included"
        }
        return included ? "Included" : "Not included"
    }
}
