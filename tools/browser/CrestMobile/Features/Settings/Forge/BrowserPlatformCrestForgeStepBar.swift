import SwiftUI
import UIKit

/// The Forge's steps as one native segmented control across the width it's
/// given, whose steps an icon doesn't use are dimmed rather than removed, so
/// nothing moves. The control fits its segments to that width itself.
struct BrowserPlatformCrestForgeStepBar: UIViewRepresentable {
    @Binding var step: BrowserCrestStudioStep
    let disabledSteps: Set<BrowserCrestStudioStep>

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: BrowserCrestStudioStep.all.map { String(localized: $0.title) })
        control.apportionsSegmentWidthsByContent = true
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        control.accessibilityIdentifier = "space-forge-steps"
        control.accessibilityLabel = String(localized: "Crest Studio step")
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.parent = self
        for (index, candidate) in BrowserCrestStudioStep.all.enumerated() {
            control.setEnabled(!disabledSteps.contains(candidate), forSegmentAt: index)
        }
        control.selectedSegmentIndex = BrowserCrestStudioStep.all.firstIndex(of: step) ?? 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        let natural = uiView.intrinsicContentSize
        return CGSize(width: proposal.width ?? natural.width, height: natural.height)
    }

    final class Coordinator: NSObject {
        var parent: BrowserPlatformCrestForgeStepBar

        init(_ parent: BrowserPlatformCrestForgeStepBar) { self.parent = parent }

        @MainActor @objc func changed(_ sender: UISegmentedControl) {
            let steps = BrowserCrestStudioStep.all
            guard steps.indices.contains(sender.selectedSegmentIndex) else { return }
            parent.step = steps[sender.selectedSegmentIndex]
        }
    }
}
