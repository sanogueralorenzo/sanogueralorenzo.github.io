import SwiftUI

struct MobilePageActionsContent: View {
    let browser: BrowserStore
    let pages: any MobilePageActions
    var downloadsAccess: MobileDownloadsMenuAccess? = nil
    var hideToolbar: (() -> Void)? = nil

    var body: some View {
        if let downloadsAccess {
            Button(action: downloadsAccess.open) {
                Label(downloadsAccess.rowTitle, systemImage: "arrow.down.circle")
            }
            .accessibilityLabel("Downloads")
            .accessibilityValue(
                BrowserChromeAccessibility.countValue(
                    downloadsAccess.newItemCount,
                    singular: "new download",
                    plural: "new downloads"
                )
            )
            .accessibilityIdentifier("page-actions-downloads")
        }

        if let notice = pages.blockedPopupNotice {
            Section("Automatic Pop-ups") {
                if notice.status.offersAllow {
                    Button {
                        pages.allowAutomaticPopupsForBlockedSite()
                    } label: {
                        Label(
                            "Allow Automatic Pop-ups",
                            systemImage: notice.status.symbol
                        )
                    }
                    .accessibilityLabel(
                        notice.allowActionAccessibilityLabel
                    )
                    .accessibilityHint(
                        notice.allowActionAccessibilityHint
                    )
                    .accessibilityIdentifier("allow-blocked-automatic-popups")
                } else {
                    Label(notice.title, systemImage: notice.status.symbol)
                        .accessibilityLabel(
                            Text(verbatim: "\(notice.title). \(notice.guidance)")
                        )
                    Text(notice.guidance)
                        .foregroundStyle(.secondary)
                }
            }
        }

        ControlGroup {
            if let url = pages.activeURL {
                ShareLink(item: url) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
            }

            Button("Copy Page Link", systemImage: "link") {
                pages.copyPageLink()
            }

            Button(
                pages.activePage?.live.isLoading == true ? "Stop" : "Reload",
                systemImage: pages.activePage?.live.isLoading == true ? "xmark" : "arrow.clockwise"
            ) {
                pages.reloadOrStop()
            }

        }
        .labelStyle(.iconOnly)

        Button(
            pages.preferredContentModeActionTitle,
            systemImage: pages.activePage?.isRequestingDesktopSite == true
                ? "iphone"
                : "desktopcomputer"
        ) {
            pages.togglePreferredContentMode()
        }

        Button(
            pages.readerModeActionTitle,
            systemImage: pages.readerModeState.actionSymbol
        ) {
            pages.toggleReaderMode()
        }
        .disabled(!pages.readerModeState.canToggle)

        Button(
            contentBlockingActionTitle,
            systemImage: pages.activePage?.isContentBlockingActive == true
                ? "shield.lefthalf.filled"
                : "shield.slash"
        ) {
            Task { await contentBlockingAction.perform() }
        }

        if let page = pages.activePage {
            sitePermissions(for: page)
            Menu("Translate Page", systemImage: "translate") {
                BrowserTranslationActions(translation: page.translation)
                    .crestMenuActionLabelStyle()
                Button("Show Translation Controls", systemImage: "rectangle.topthird.inset.filled") {
                    page.translation.present()
                }
            }
            .disabled(page.readerModeState.isActive)
            .task { await page.translation.refreshInstalledLanguages() }
        }

        Button("Find in Page", systemImage: "text.magnifyingglass") {
            pages.presentFind()
        }

        if let hideToolbar {
            Button("Hide Toolbar", systemImage: "chevron.down") {
                hideToolbar()
            }
        }

        Section("Page Zoom") {
            Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                pages.zoomOut()
            }

            Button("Actual Size (\(pages.pageZoomLabel))", systemImage: "1.magnifyingglass") {
                pages.resetZoom()
            }

            Button("Zoom In", systemImage: "plus.magnifyingglass") {
                pages.zoomIn()
            }
        }

        Section {
            Button("Copy as Markdown", systemImage: "text.badge.checkmark") {
                pages.copyPageLinkAsMarkdown()
            }

            Menu("Share & Export…", systemImage: "square.and.arrow.up") {
                Group {
                    if let url = pages.activeURL {
                        ShareLink(item: url) {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }
                    }

                    Button("Print…", systemImage: "printer") {
                        pages.printPage()
                    }

                    Menu("Export as PDF…", systemImage: "doc.richtext") {
                        ForEach(MobileBrowserFileExportDestination.all) {
                            destination in
                            Button(
                                destination.title,
                                systemImage: destination.symbol
                            ) {
                                pages.exportPDF(to: destination)
                            }
                        }
                        .crestMenuActionLabelStyle()
                    }

                    Menu("Export Web Archive…", systemImage: "archivebox") {
                        ForEach(MobileBrowserFileExportDestination.all) {
                            destination in
                            Button(
                                destination.title,
                                systemImage: destination.symbol
                            ) {
                                pages.exportWebArchive(to: destination)
                            }
                        }
                        .crestMenuActionLabelStyle()
                    }
                }
                .crestMenuActionLabelStyle()
            }
        }
    }

    @ViewBuilder
    private func sitePermissions(for page: MobileBrowserPage) -> some View {
        if let origin = page.live.documentURL.flatMap(SiteOrigin.init(url:)) {
            Menu("Site Permissions", systemImage: "slider.horizontal.3") {
                // A page on iOS cannot share the screen, so that choice is
                // not offered here.
                ForEach(SitePermission.all.filter { $0 != .screenSharing }, id: \.self) { permission in
                    Picker(
                        permission.title,
                        selection: Binding {
                            page.permissionCenter.decision(for: permission, origin: origin, in: page.spaceID)
                        } set: { decision in
                            page.permissionCenter.setDecision(
                                decision, for: permission, origin: origin, in: page.spaceID)
                        }
                    ) {
                        Text(permission.askChoiceTitle).tag(SitePermissionDecision.ask)
                        Text("Allow").tag(SitePermissionDecision.grantPersistently)
                        Text("Block").tag(SitePermissionDecision.denyPersistently)
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var contentBlockingAction: MobileContentBlockingAction {
        MobileContentBlockingAction(browser: browser, pages: pages)
    }

    private var contentBlockingActionTitle: LocalizedStringResource {
        ContentBlockingPolicy.switchTitle(for: browser.shownSpace?.settings.browsingPreferences.contentBlocking)
    }
}
