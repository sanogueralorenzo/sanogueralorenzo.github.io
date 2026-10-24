import SwiftUI

@MainActor @Observable
final class SpaceForegroundPresentation {
    struct Tone: Equatable {
        let id: UUID
        let white: Double
    }

    private(set) var position: CGFloat?
    @ObservationIgnored private var presentation: SpacePagerPresentation?
    @ObservationIgnored private var tones: [Tone] = []
    @ObservationIgnored private var selectedSpaceID: UUID?
    @ObservationIgnored private var activeTransition: SpacePagerSettlement?

    func connect(_ presentation: SpacePagerPresentation?, tones: [Tone], selectedSpaceID: UUID?) {
        if self.presentation !== presentation { disconnect() }
        self.presentation = presentation
        self.tones = tones
        self.selectedSpaceID = selectedSpaceID
        presentation?.observe(owner: self) { [weak self] in self?.receive($0) }
        if presentation?.snapshot == nil { receive(nil) }
    }

    func disconnect() {
        presentation?.removeObserver(owner: self)
        presentation = nil
        activeTransition = nil
    }

    private func receive(_ snapshot: SpacePagerPresentation.Snapshot?) {
        if let transition = snapshot?.transition, activeTransition == transition { return }
        activeTransition = snapshot?.transition
        if let snapshot, snapshot.spaceIDs == tones.map(\.id), let transition = snapshot.transition {
            // SwiftUI interpolates this leaf's position, including any crossed
            // color boundary, with the pager's single release curve. Do not
            // restart it from main-thread display-link samples.
            withAnimation(transition.animation) { position = transition.endPosition }
            return
        }
        let value: CGFloat
        if let snapshot, !tones.isEmpty, snapshot.spaceIDs == tones.map(\.id), snapshot.position.isFinite {
            value = snapshot.position
        } else {
            value = CGFloat(tones.firstIndex { $0.id == selectedSpaceID } ?? 0)
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { position = value }
    }

    static func white(at position: CGFloat, tones: [Tone]) -> Double {
        guard let sample = SpacePagerInterpolation(position: position, count: tones.count) else { return 1 }
        let start = tones[sample.lower].white
        return start + (tones[sample.upper].white - start) * Double(sample.fraction)
    }
}
