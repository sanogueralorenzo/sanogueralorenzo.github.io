import SwiftUI

/// The share sheet's Crest entry: nothing while the link is handed to Crest,
/// or a short notice when it could not be.
struct CrestShareView: View {
    // MARK: - Variables

    let model: CrestShareModel

    var body: some View {
        if let notice = model.notice {
            NavigationStack {
                ContentUnavailableView {
                    Label {
                        Text(notice.title)
                    } icon: {
                        Image(systemName: notice.systemImage)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: model.close)
                    }
                }
            }
        } else {
            Color.clear
        }
    }
}
