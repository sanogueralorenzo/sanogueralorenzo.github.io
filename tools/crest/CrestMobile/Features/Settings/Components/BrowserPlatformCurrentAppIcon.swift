import SwiftUI
import UIKit

/// Follows the icon selected for the Home Screen while it is displayed.
struct BrowserPlatformCurrentAppIcon: View {
    @State private var selectedName = UIApplication.shared.alternateIconName

    var body: some View {
        BrowserPlatformAppIcon(name: selectedName)
            .onAppear { selectedName = UIApplication.shared.alternateIconName }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                selectedName = UIApplication.shared.alternateIconName
            }
    }
}
