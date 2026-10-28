import SwiftUI

struct CrestStartPageMark: View {
    var body: some View {
        Image("CrestPreview")
            .resizable()
            .scaledToFit()
    }
}

#if DEBUG
    #Preview("Component") {
        CrestStartPageMark().frame(width: 80, height: 80).padding()
    }
#endif
