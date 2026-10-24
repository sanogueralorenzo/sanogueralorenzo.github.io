import SwiftUI

struct BrowserReloadFeedbackIcon: View {
    private static let restingRotation = 0.0
    private static let pressedRotation = Double(CrestLayout.reloadQuarterTurn)
    private static let phaseDuration = CrestMotion.reloadFeedbackPhaseDuration

    let systemName: String
    let pulse: Int
    let animates: Bool
    let pointSize: CGFloat
    let feedbackDidComplete: (Int) -> Void

    @State private var rotation = Self.restingRotation
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        BrowserChromeSymbolLabel(
            systemName: systemName,
            pointSize: pointSize
        )
        .rotationEffect(.degrees(rotation), anchor: .center)
        .onChange(of: pulse) {
            playFeedback()
        }
        .onChange(of: animates) {
            updateAnimationAvailability()
        }
        .onDisappear(perform: cancelFeedback)
    }

    private func playFeedback() {
        cancelFeedback()
        resetRotation()
        guard animates else {
            feedbackDidComplete(pulse)
            return
        }

        let playingPulse = pulse
        feedbackTask = Task { @MainActor in
            withAnimation(CrestMotion.reloadTurnOut) {
                rotation = Self.pressedRotation
            }
            try? await Task.sleep(for: Self.phaseDuration)
            guard !Task.isCancelled else { return }
            withAnimation(
                CrestMotion.reloadTurnIn,
                completionCriteria: .logicallyComplete
            ) {
                rotation = Self.restingRotation
            } completion: {
                feedbackDidComplete(playingPulse)
            }
        }
    }

    private func updateAnimationAvailability() {
        guard !animates else { return }
        cancelFeedback()
        resetRotation()
        feedbackDidComplete(pulse)
    }

    private func cancelFeedback() {
        feedbackTask?.cancel()
        feedbackTask = nil
    }

    private func resetRotation() {
        withTransaction(Transaction(animation: nil)) {
            rotation = Self.restingRotation
        }
    }
}
