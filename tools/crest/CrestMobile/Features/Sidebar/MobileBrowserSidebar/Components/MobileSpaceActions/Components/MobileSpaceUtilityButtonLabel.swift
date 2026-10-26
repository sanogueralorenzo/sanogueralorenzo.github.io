import SwiftUI

struct MobileSpaceUtilityButtonLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }
}

#if DEBUG
    #Preview("Component") {
        HStack {
            MobileSpaceUtilityButtonLabel(systemImage: "archivebox")
            MobileSpaceUtilityButtonLabel(systemImage: "gearshape")
        }.padding()
    }
#endif
