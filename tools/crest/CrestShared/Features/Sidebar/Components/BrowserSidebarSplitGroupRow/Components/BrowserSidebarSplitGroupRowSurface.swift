import SwiftUI

/// Measures the split as one insertion slot; its header owns the group drag.
struct BrowserSidebarSplitGroupRowSurface: ViewModifier {
    let configuration: BrowserSidebarSplitGroupRowConfiguration
    let interaction: BrowserSidebarSplitGroupRowInteractionContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sidebarLayerDepth) private var depth

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .background {
                CrestSurfaceLayer(
                    shape: containerShape,
                    hoverTint: configuration.isPresented ? CrestColor.hover : nil
                )
                .overlay { if isMultiSelected { containerShape.fill(CrestColor.hover) } }
                .overlay {
                    if let tint = configuration.tint {
                        containerShape.fill(
                            tint.color.opacity(
                                configuration.isPresented ? 0.16 : 0.10
                            )
                        )
                    }
                }
            }
            .animation(surfaceAnimation, value: configuration.isPresented)
            .animation(surfaceAnimation, value: isMultiSelected)
            // In the same column as every other layer, with the space it keeps
            // from its neighbours inside the row, so drag geometry includes the
            // resting separation.
            .padding(.horizontal, BrowserSidebarMetrics.layerInset)
            .padding(.vertical, BrowserSidebarMetrics.containerSpacing)
            .contentShape(.rect)
            .modifier(
                BrowserTabSelectionTarget(
                    tabID: configuration.members.first?.id, browser: configuration.browser,
                    assignment: configuration.assignment,
                    isEnabled: configuration.isAvailableForDisplay && !interaction.isRenaming)
            )
            .browserSidebarReorderContainer(
                item: .splitGroup(configuration.dragItem),
                section: .tabs(placement: configuration.placement, folderID: configuration.folderID),
                reorder: configuration.reorderContext,
                isEnabled: configuration.isAvailableForDisplay && configuration.capabilities.supportsOrganization
            )
            .crestCollectionItemTransition()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                "Split View with \(configuration.members.count) tabs"
            )
    }

    private var isMultiSelected: Bool {
        configuration.members.contains {
            BrowserSidebarSelection.showsSelected(.tab($0.id), in: configuration.context)
        }
    }

    private var containerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(depth: depth), style: .continuous)
    }

    private var surfaceAnimation: Animation? {
        CrestMotion.surface.unlessReducingMotion(reduceMotion)
    }
}
