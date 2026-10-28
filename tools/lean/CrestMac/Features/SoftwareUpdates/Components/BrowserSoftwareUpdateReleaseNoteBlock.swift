import SwiftUI

struct BrowserSoftwareUpdateReleaseNoteBlock: View {
    let block: BrowserSoftwareUpdateReleaseNotesDocument.Block

    @ViewBuilder
    var body: some View {
        switch block.kind {
        case .heading(let level):
            Text(block.text)
                .font(headingFont(level: level))
                .padding(.top, level <= 2 ? CrestSpacing.small : CrestSpacing.extraSmall)
        case .paragraph:
            Text(block.text)
                .font(.body)
                .lineSpacing(CrestSpacing.extraExtraSmall)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: CrestSpacing.small) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5, weight: .semibold))
                    .foregroundStyle(CrestBrandTheme.accent)
                    .accessibilityHidden(true)

                Text(block.text)
                    .font(.body)
                    .lineSpacing(CrestSpacing.extraExtraSmall)
            }
        case .divider:
            Divider()
                .padding(.vertical, CrestSpacing.extraSmall)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1, 2: .title3.weight(.semibold)
        case 3: .headline
        default: .subheadline.weight(.semibold)
        }
    }
}
