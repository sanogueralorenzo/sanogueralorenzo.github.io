import SwiftUI

/// The former Crest install popover, supplied with Chromium's verified package
/// and permission warnings instead of a WebKit compatibility translation.
struct BrowserChromeWebStoreInstallView: View {
    @Bindable var model: ChromiumExtensionInstallation
    @State private var isAccessExpanded = true
    @State private var isSelectingSpaces = false

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.large) {
            if isSelectingSpaces {
                BrowserExtensionInstallSpacesPage(
                    primarySpaceName: model.space.name,
                    spaces: model.destinations, selection: $model.selectedSpaces,
                    goBack: { isSelectingSpaces = false })
            } else {
                HStack(alignment: .center, spacing: CrestSpacing.medium) {
                    BrowserExtensionIconView(
                        image: model.questionIcon, size: BrowserExtensionsMetrics.installReviewIconSize)
                    VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                        Text(model.completed ? "Extension Installed" : model.questionName ?? "Install Extension")
                            .font(.title3.weight(.semibold))
                        if model.question != nil {
                            Label("Verified Chrome Web Store package", systemImage: "checkmark.seal.fill")
                                .font(.caption).foregroundStyle(.green)
                        }
                    }
                    Spacer(minLength: CrestSpacing.medium)
                }
                if model.preparing {
                    if let downloaded = model.downloaded, downloaded < 1 {
                        ProgressView("Downloading extension…", value: downloaded).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: CrestSpacing.medium) {
                            ProgressView().controlSize(.small)
                            Text("Preparing extension…").foregroundStyle(.secondary)
                        }
                    }
                } else if model.completed {
                    Label(
                        "\(model.questionName ?? "Extension") is ready in \(model.space.name).",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                    if model.installedCount > 1 {
                        Text("Installed in \(model.installedCount - 1) additional Spaces.").font(.callout)
                    }
                } else if let question = model.question {
                    VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                        if !question.summary.isEmpty {
                            Text(question.summary).font(.callout).foregroundStyle(.secondary).fixedSize(
                                horizontal: false, vertical: true)
                        }
                        LabeledContent("Install In", value: "\(model.space.name) Space").font(.callout)
                        LabeledContent("Version", value: question.version).font(.callout)
                        Text("Only install extensions you trust. Review the access below before installing.")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup(isExpanded: $isAccessExpanded) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                                    BrowserExtensionInstallAccessGroup(
                                        title: "Permissions and Website Access",
                                        values: question.permissions,
                                        emptyText: "No additional browser permissions requested.")
                                    if model.canWithhold {
                                        Toggle("Withhold website access until I grant it", isOn: $model.withhold)
                                            .toggleStyle(.checkbox).font(.caption)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: BrowserExtensionInstallMetrics.accessReviewMaximumHeight)
                            .padding(.top, CrestSpacing.small)
                        } label: {
                            Label("Review Access and Compatibility", systemImage: "hand.raised.fill")
                                .font(.callout.weight(.semibold))
                        }
                    }
                    .disabled(model.installing)
                    Button("Install in other Spaces…") { isSelectingSpaces = true }
                        .disabled(model.installing)
                    if !model.selectedSpaces.isEmpty {
                        Text("Additional Spaces: \(model.selectedSpaces.count)").font(.caption).foregroundStyle(
                            .secondary)
                    }
                }
                if let failure = model.failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    if model.installedCount > 0 {
                        Text("Installed in \(model.installedCount) Spaces before this error.").font(.caption)
                    }
                }
                Divider()
                HStack {
                    Spacer()
                    if model.completed {
                        Button("Done", action: model.dismiss).buttonStyle(.borderedProminent).keyboardShortcut(
                            .defaultAction)
                    } else {
                        Button("Cancel", role: .cancel, action: model.dismiss).disabled(model.installing)
                        if model.question != nil && model.failure == nil {
                            Button(action: model.accept) {
                                if model.installing {
                                    ProgressView().controlSize(.small).accessibilityLabel("Adding extension")
                                } else {
                                    Text("Add Extension")
                                }
                            }
                            .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                            .disabled(!model.canAccept || model.installing)
                        }
                    }
                }
            }
        }
        .padding(CrestSpacing.extraLarge)
        .frame(width: BrowserExtensionInstallMetrics.width)
        .interactiveDismissDisabled(model.installing)
        .onChange(of: model.isAuthorized) { _, authorized in if !authorized { model.dismiss() } }
    }
}
