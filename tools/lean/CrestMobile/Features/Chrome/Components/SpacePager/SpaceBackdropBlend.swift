import SwiftUI
import UIKit

/// The touch adapter for the shared Space presentation. Only background layers
/// receive scroll samples; tab trees and web views are never hosted here.
struct SpaceBackdropBlend<Background: View>: UIViewControllerRepresentable {
    let spaces: [SpaceModel]
    let selectedSpace: SpaceModel?
    @ViewBuilder let background: (SpaceModel?) -> Background

    func makeUIViewController(context: Context) -> SpaceBackdropBlendController<Background> {
        SpaceBackdropBlendController<Background>()
    }

    func updateUIViewController(_ controller: SpaceBackdropBlendController<Background>, context: Context) {
        let environment = context.environment
        controller.update(
            spaces: spaces, selectedSpace: selectedSpace,
            presentation: environment.spacePagerPresentation
        ) {
            TouchSpaceBackdropRoot(background: background($0), colorScheme: environment.colorScheme)
        }
    }

    static func dismantleUIViewController(_ controller: SpaceBackdropBlendController<Background>, coordinator: ()) {
        controller.disconnect()
    }
}

@MainActor
final class SpaceBackdropBlendController<Background: View>: UIViewController {
    private weak var presentation: SpacePagerPresentation?
    private var spaces: [SpaceModel] = []
    private var selectedSpace: SpaceModel?
    private var makeBackground: ((SpaceModel?) -> TouchSpaceBackdropRoot<Background>)?
    private var hosts: [BrowserSpaceRuntimeAssignment: UIHostingController<TouchSpaceBackdropRoot<Background>>] = [:]
    private var fallback: UIHostingController<TouchSpaceBackdropRoot<Background>>?

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for child in children where child.view.frame != view.bounds { child.view.frame = view.bounds }
    }

    func update(
        spaces: [SpaceModel], selectedSpace: SpaceModel?, presentation: SpacePagerPresentation?,
        makeBackground: @escaping (SpaceModel?) -> TouchSpaceBackdropRoot<Background>
    ) {
        let connectionChanged = self.presentation !== presentation
        if connectionChanged { disconnect() }
        self.presentation = presentation
        self.spaces = spaces
        self.selectedSpace = selectedSpace
        self.makeBackground = makeBackground
        let valid = Set(spaces.map(BrowserSpaceRuntimeAssignment.init(space:)))
        for key in hosts.keys where !valid.contains(key) { remove(hosts.removeValue(forKey: key)) }
        for space in spaces { hosts[BrowserSpaceRuntimeAssignment(space: space)]?.rootView = makeBackground(space) }
        if spaces.isEmpty {
            if let fallback {
                fallback.rootView = makeBackground(selectedSpace)
            } else {
                fallback = add(makeBackground(selectedSpace))
            }
        } else {
            remove(fallback)
            fallback = nil
        }
        if connectionChanged, let presentation {
            presentation.observe(owner: self) { [weak self] in self?.receive($0) }
            if presentation.snapshot == nil { receive(nil) }
        } else {
            receive(presentation?.snapshot)
        }
    }

    private func receive(_ snapshot: SpacePagerPresentation.Snapshot?) {
        guard !spaces.isEmpty, let makeBackground else { return }
        let position =
            snapshot?.spaceIDs == spaces.map(\.id)
            ? snapshot?.position ?? 0 : CGFloat(spaces.firstIndex { $0.id == selectedSpace?.id } ?? 0)
        guard let interpolation = SpacePagerInterpolation(position: position, count: spaces.count) else { return }
        let range = max(0, interpolation.lower - 1)...min(spaces.count - 1, interpolation.upper + 1)
        let required = Set(range.map { BrowserSpaceRuntimeAssignment(space: spaces[$0]) })
        for index in range {
            let space = spaces[index]
            let key = BrowserSpaceRuntimeAssignment(space: space)
            if hosts[key] == nil { hosts[key] = add(makeBackground(space)) }
        }
        for key in hosts.keys where !required.contains(key) { remove(hosts.removeValue(forKey: key)) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in range {
            let layer = hosts[BrowserSpaceRuntimeAssignment(space: spaces[index])]?.view.layer
            layer?.zPosition = CGFloat(index)
            layer?.opacity = SpacePagerInterpolation.backdropOpacity(at: position, index: index)
        }
        CATransaction.commit()
    }

    private func add(_ root: TouchSpaceBackdropRoot<Background>) -> UIHostingController<
        TouchSpaceBackdropRoot<Background>
    > {
        let host = UIHostingController(rootView: root)
        host.safeAreaRegions = []
        host.sizingOptions = []
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        return host
    }

    private func remove(_ host: UIHostingController<TouchSpaceBackdropRoot<Background>>?) {
        host?.willMove(toParent: nil)
        host?.view.removeFromSuperview()
        host?.removeFromParent()
    }

    func disconnect() {
        presentation?.removeObserver(owner: self)
        presentation = nil
    }
}

/// A concrete hosting root keeps appearance updates separate from native opacity.
struct TouchSpaceBackdropRoot<Background: View>: View {
    let background: Background
    let colorScheme: ColorScheme

    var body: some View {
        background
            .environment(\.colorScheme, colorScheme)
            .transaction { $0.disablesAnimations = true }
    }
}
