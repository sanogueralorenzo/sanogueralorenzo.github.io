import AppKit
import SwiftUI

/// The Forge's steps as one native segmented control, whose steps an icon
/// doesn't use are dimmed rather than removed, so nothing moves.
struct BrowserPlatformCrestForgeStepBar: NSViewRepresentable {
    @Binding var step: BrowserCrestStudioStep
    let disabledSteps: Set<BrowserCrestStudioStep>

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: BrowserCrestStudioStep.all.map { String(localized: $0.title) },
            trackingMode: .selectOne, target: context.coordinator,
            action: #selector(Coordinator.changed(_:)))
        control.segmentStyle = .automatic
        control.setAccessibilityIdentifier("space-forge-steps")
        control.setAccessibilityLabel(String(localized: "Crest Studio step"))
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        for (index, candidate) in BrowserCrestStudioStep.all.enumerated() {
            control.setEnabled(!disabledSteps.contains(candidate), forSegment: index)
        }
        control.selectedSegment = BrowserCrestStudioStep.all.firstIndex(of: step) ?? 0
    }

    final class Coordinator: NSObject {
        var parent: BrowserPlatformCrestForgeStepBar

        init(_ parent: BrowserPlatformCrestForgeStepBar) { self.parent = parent }

        @MainActor @objc func changed(_ sender: NSSegmentedControl) {
            let steps = BrowserCrestStudioStep.all
            guard steps.indices.contains(sender.selectedSegment) else { return }
            parent.step = steps[sender.selectedSegment]
        }
    }
}
