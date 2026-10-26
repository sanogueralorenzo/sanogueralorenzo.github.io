import SwiftUI

struct BrowserSidebarWidgetDeckStepper: View {
    let instances: [BrowserSidebarWidgetInstance]
    let selectedInstanceID: BrowserSidebarWidgetID?
    let select: (BrowserSidebarWidgetID) -> Void
    let cycle: (BrowserSidebarWidgetCarouselDirection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    var body: some View {
        ViewThatFits(in: .vertical) {
            fullPageIndicator
            compactStepper
        }
        .frame(width: BrowserSidebarWidgetDeckStyle.sideStepperRailWidth)
        .focusable(interactions: .activate)
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            switch press.key {
            case .leftArrow, .upArrow:
                cycle(.previous)
            case .rightArrow, .downArrow:
                cycle(.next)
            default:
                return .ignored
            }
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose sidebar widget")
        .accessibilityValue(selectionValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                cycle(.next)
            case .decrement:
                cycle(.previous)
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder private var fullPageIndicator: some View {
        #if os(iOS)
            BrowserSidebarWidgetVerticalPageControl(
                numberOfPages: instances.count,
                currentPage: selectedIndex,
                selectPage: selectPage
            )
        #else
            indicatorColumn
        #endif
    }

    private var indicatorColumn: some View {
        VStack(spacing: 0) {
            ForEach(instances) { instance in
                indicator(for: instance)
            }
        }
        .animation(selectionAnimation, value: selectedInstanceID)
    }

    private func indicator(
        for instance: BrowserSidebarWidgetInstance
    ) -> some View {
        let isSelected = instance.id == selectedInstanceID
        let indicatorSize = BrowserSidebarWidgetDeckStyle.indicatorSize(
            isSelected: isSelected
        )
        return Button {
            select(instance.id)
        } label: {
            Circle()
                .fill(
                    isSelected
                        ? Color.primary.opacity(
                            BrowserSidebarWidgetDeckStyle.indicatorActiveOpacity
                        )
                        : Color.secondary.opacity(
                            BrowserSidebarWidgetDeckStyle.indicatorInactiveOpacity
                        )
                )
                .frame(
                    width: indicatorSize.width,
                    height: indicatorSize.height
                )
                .frame(
                    minWidth: BrowserSidebarWidgetDeckStyle.indicatorHitWidth,
                    minHeight: BrowserSidebarWidgetDeckStyle.indicatorDotHitHeight
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(indicatorLabel(for: instance))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedIndex: Int {
        guard
            let selectedInstanceID,
            let index = instances.firstIndex(where: { $0.id == selectedInstanceID })
        else { return 0 }
        return index
    }

    private func selectPage(_ index: Int) {
        guard instances.indices.contains(index) else { return }
        select(instances[index].id)
    }

    private var compactStepper: some View {
        VStack(spacing: 0) {
            stepButton(.previous, symbol: "chevron.up")
            Text(verbatim: compactSelectionValue)
                .font(CrestTypography.compactMetadata.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(
                    .horizontal,
                    BrowserSidebarWidgetDeckStyle.stepperBadgeHorizontalPadding
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .background(.quaternary, in: .capsule)
            stepButton(.next, symbol: "chevron.down")
        }
    }

    private var selectionValue: String {
        guard
            let selectedInstanceID,
            let selectedIndex = instances.firstIndex(where: { $0.id == selectedInstanceID })
        else { return "\(instances.count) widgets" }
        return "\(selectedIndex + 1) of \(instances.count)"
    }

    private var compactSelectionValue: String {
        guard
            let selectedInstanceID,
            let selectedIndex = instances.firstIndex(where: { $0.id == selectedInstanceID })
        else { return "\(instances.count)" }
        return "\(selectedIndex + 1)/\(instances.count)"
    }

    private var selectionAnimation: Animation? {
        CrestMotion.selection.unlessReducingMotion(reduceMotion)
    }

    /// The deck wraps, so a step control is never a dead end.
    private func stepButton(
        _ direction: BrowserSidebarWidgetCarouselDirection,
        symbol: String
    ) -> some View {
        Button {
            cycle(direction)
        } label: {
            Image(systemName: symbol)
                .frame(
                    minWidth: BrowserSidebarWidgetDeckStyle.indicatorHitWidth,
                    minHeight: BrowserSidebarWidgetDeckStyle.indicatorHitHeight
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(direction.accessibilityLabel)
        )
    }

    private func indicatorLabel(
        for instance: BrowserSidebarWidgetInstance
    ) -> String {
        let position =
            instances.firstIndex(where: { $0.id == instance.id })
            .map { $0 + 1 } ?? 1
        return "Widget \(position), \(instance.presentation.deckDescription)"
    }
}
