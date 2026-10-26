import SwiftUI

struct MobileCompactChromeTransitionModifier: ViewModifier {
    let transition: MobileCompactChromeTransition
    let transitionEnded: (CGSize) -> Void

    @State private var committedDuringDrag = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(transitionGesture, including: .all)
    }

    private var transitionGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard !committedDuringDrag,
                    transition.commits(predictedEndTranslation: value.translation)
                else { return }
                committedDuringDrag = true
                transitionEnded(value.translation)
            }
            .onEnded { value in
                defer { committedDuringDrag = false }
                guard !committedDuringDrag else { return }
                transitionEnded(value.predictedEndTranslation)
            }
    }
}
