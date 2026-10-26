import SwiftUI

/// Keeps website controls, permission prompts and extension popups anchored to More.
struct BrowserSiteControlHost<Content: View>: View {
    let configuration: BrowserSiteControlConfiguration

    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.browserSiteControlAnchor) private var anchor

    var body: some View {
        content()
            .popover(isPresented: presentationBinding, arrowEdge: .top) {
                Group {
                    if let request = configuration.page.sitePermissionRequests.current {
                        BrowserPagePermissionPrompt(
                            request: request,
                            controller: configuration.page.sitePermissionRequests
                        )
                    } else {
                        BrowserSiteControlPopover(
                            configuration: configuration,
                            dismiss: { presentationBinding.wrappedValue = false }
                        )
                    }
                }
                .modifier(BrowserSiteControlPopoverStyle())
                .modifier(BrowserDeviceAppearanceEnvironment())
            }
            .overlay(alignment: .topTrailing) {
                if configuration.page.blockedPopupNotice != nil {
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                        .overlay { Circle().stroke(.background, lineWidth: 1) }
                        .padding(.trailing, CrestSpacing.small)
                        .padding(.top, CrestSpacing.extraSmall)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            // More opens the window's extension list, so it is where an
            // extension popup goes when the keyboard asked for one and the
            // extension has no pinned tile to anchor to.
            .background {
                if let anchor { BrowserSiteControlAnchorHost(anchor: anchor) }
            }
            .pagePermissionHost(configuration.page.sitePermissionRequests)
            .onChange(of: configuration.page.sitePermissionRequests.current?.id) {
                configuration.presentationChanged(presentationBinding.wrappedValue)
            }
            .onDisappear {
                guard isPresented else { return }
                presentationBinding.wrappedValue = false
            }
            .onChange(of: BrowserSpaceRuntimeAssignment(space: configuration.space)) {
                // The navigation row survives a Space change; its old
                // site's popover must still end at that assignment boundary.
                guard isPresented else { return }
                presentationBinding.wrappedValue = false
            }
    }

    private var presentationBinding: Binding<Bool> {
        Binding {
            isPresented || configuration.page.sitePermissionRequests.current != nil
        } set: { isPresented in
            if !isPresented && configuration.page.sitePermissionRequests.current != nil {
                configuration.page.sitePermissionRequests.cancelAll()
            }
            guard isPresented != self.isPresented else { return }
            self.isPresented = isPresented
            configuration.presentationChanged(isPresented)
        }
    }
}
