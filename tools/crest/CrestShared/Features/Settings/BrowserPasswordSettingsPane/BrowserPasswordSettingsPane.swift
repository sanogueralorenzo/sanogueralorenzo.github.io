import SwiftUI
import UniformTypeIdentifiers

// MARK: - Types

struct BrowserSettingsSpaceDataRequest: Equatable {
    let assignment: BrowserSpaceRuntimeAssignment?
    let canRevealSpaceData: Bool
}

/// Shared Space password preferences and manager, configured by each platform's layout.
struct BrowserPasswordSettingsPane: View {
    private static let disabledDescription = "Saved passwords stay here until you delete them."

    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let layout: BrowserPasswordSettingsLayout
    /// Accepts the Settings window's search query.
    @Binding var searchText: String
    /// Opens the password manager when the platform presents it separately.
    var manage: (() -> Void)?
    /// The one Space whose passwords the pane shows, or nil to pick one.
    let fixedSpaceID: UUID?

    @State private var credentials: BrowserCredentialSpaceStore
    @State private var pickedSpaceID: UUID?
    private var selectedSpaceID: UUID? { fixedSpaceID ?? pickedSpaceID }
    private var selectedSpaceBinding: Binding<UUID?> {
        Binding(get: { selectedSpaceID }, set: { if fixedSpaceID == nil { pickedSpaceID = $0 } })
    }
    @State private var credentialPendingDeletion: CredentialDescriptor?
    @State private var credentialDetailRequest: BrowserCredentialDetailRequest?
    @State private var confirmsPlaintextExport = false
    @State private var isExporting = false
    @State private var isChoosingImportFile = false
    @State private var isSelectingCredentials = false
    @State private var selectedCredentialIDs: Set<UUID> = []
    @State private var confirmsSelectionDeletion = false
    @State private var confirmsUnreadableRemoval = false

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        layout: BrowserPasswordSettingsLayout,
        searchText: Binding<String> = .constant(""),
        manage: (() -> Void)? = nil,
        fixedSpaceID: UUID? = nil
    ) {
        self.browser = browser
        self.spaceAccess = spaceAccess
        self.layout = layout
        _searchText = searchText
        self.manage = manage
        self.fixedSpaceID = fixedSpaceID
        _credentials = State(
            initialValue: BrowserCredentialSpaceStore(browser: browser)
        )
    }

    var body: some View {
        BrowserSettingsPane(.passwords) {
            settingsSections
        }
        .crestRepairsSpaceSelection(selectedSpaceBinding, in: browser)
        .task(id: credentialLoadRequest) {
            await credentials.load(
                in: selectedSpaceID,
                accessController: spaceAccess
            )
        }
        .onChange(of: credentialLoadRequest, initial: true) { previous, request in
            if previous.assignment != request.assignment
                || !request.canRevealSpaceData
            {
                clearSensitivePresentation()
            }
        }
        .alert(
            "Delete Password?",
            isPresented: deletionAlertIsPresented,
            presenting: credentialPendingDeletion
        ) { descriptor in
            Button("Delete", role: .destructive) {
                credentialPendingDeletion = nil
                credentials.delete(
                    descriptor,
                    reloading: selectedSpaceID,
                    accessController: spaceAccess
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: { descriptor in
            Text(credentials.deletionMessage(for: descriptor, in: space))
        }
        .alert(
            "Export Passwords as Plaintext?",
            isPresented: $confirmsPlaintextExport
        ) {
            Button("Export…") { prepareExport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The CSV file will contain readable usernames and passwords from only the selected Space. Anyone with the file can read them. Crest will authenticate you before opening the \(layout.exportDestinationName)."
            )
        }
        .confirmationDialog(
            "Delete Selected Passwords?",
            isPresented: $confirmsSelectionDeletion,
            titleVisibility: .visible
        ) {
            Button(selectionDeletionButtonLabel, role: .destructive) {
                deleteSelectedCredentials()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(selectionDeletionMessage)
        }
        .alert(
            "Remove Passwords Crest Can’t Read?",
            isPresented: $confirmsUnreadableRemoval
        ) {
            Button("Remove", role: .destructive) {
                guard let selectedSpaceID else { return }
                credentials.deleteUnreadable(in: selectedSpaceID, accessController: spaceAccess)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Crest can’t show or fill them. This cannot be undone.")
        }
        .sheet(item: $credentialDetailRequest) { request in
            BrowserCredentialDetailView(
                browser: browser,
                spaceAccess: spaceAccess,
                request: request
            )
            .id(request.id)
        }
        .sheet(item: $credentials.importReview) { review in
            BrowserCredentialImportReviewView(
                initialReviewID: review.id,
                credentials: credentials,
                browser: browser,
                spaceAccess: spaceAccess
            )
        }
        .alert(
            "Password Import Finished",
            isPresented: importSummaryIsPresented,
            presenting: credentials.importSummary
        ) { _ in
            Button("OK") { credentials.importSummary = nil }
        } message: { summary in
            Text(
                "Accepted \(summary.acceptedCount), skipped \(summary.skippedCount), reviewed \(summary.warningCount) warnings, and rejected \(summary.rejectedCount) from the selected file."
            )
        }
        .fileImporter(
            isPresented: $isChoosingImportFile,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            openImportResult(result)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: credentials.exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: credentials.exportFilename
        ) { result in
            if case .failure = result {
                credentials.reportExportFailure()
            }
            credentials.exportDocument = nil
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var settingsSections: some View {
        if fixedSpaceID == nil {
            Section("System passkeys") {
                BrowserPasskeyAccessView()
            }

            Section {
                CrestSpaceMenuPicker(
                    "Space",
                    selection: selectedSpaceBinding,
                    spaces: CrestSpaceIdentity.list(browser.spaceModels)
                )
            }
        }

        if let space {
            if canRevealSelectedSpaceData {
                Section {
                    Toggle(
                        "Use Crest Passwords",
                        isOn: browser.credentialPreferenceBinding(
                            \.isEnabled,
                            in: space
                        )
                    )
                    .accessibilityIdentifier(
                        "space-crest-passwords-enabled"
                    )

                    Group {
                        if layout.showsCredentialPreferences {
                            credentialPreferences(in: space)
                        }

                        if layout.showsManageAction {
                            Button("Manage Saved Passwords…") {
                                manage?()
                            }
                        }

                        if layout.showsExportAction {
                            Button("Export Passwords…") {
                                confirmsPlaintextExport = true
                            }
                            .disabled(
                                credentials.descriptors.isEmpty
                                    || credentials.isPreparingExport
                            )
                            .accessibilityIdentifier(
                                "export-space-passwords"
                            )
                        }
                    }
                    .disabled(!space.settings.credentialPreferences.isEnabled)
                } header: {
                    Text("Crest Passwords")
                } footer: {
                    if !space.settings.credentialPreferences.isEnabled {
                        Text(Self.disabledDescription).crestFormFootnote()
                    } else if layout.showsCredentialPreferences {
                        CrestFormFootnote("iCloud Keychain and Passwords choices apply to this device only.")
                    }
                }

                if layout.showsSavedPasswords {
                    Section {
                        if !credentials.descriptors.isEmpty || !searchText.isEmpty {
                            BrowserCredentialSearchField(
                                title: "Search saved passwords",
                                text: $searchText,
                                accessibilityIdentifier: "saved-password-search"
                            )
                        }
                        passwordManagerActions
                        savedPasswords
                        if credentials.unreadableCount > 0 {
                            unreadablePasswords
                        }
                    } header: {
                        Text("Saved passwords")
                    } footer: {
                        if !credentials.descriptors.isEmpty {
                            Text(passwordCountLabel).crestFormFootnote()
                        }
                    }
                }

                if let errorMessage = credentials.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            } else {
                BrowserSettingsPrivateSpaceAccessSection(
                    space: space,
                    accessController: spaceAccess,
                    detail: "Unlock this Space to see its passwords."
                )
            }
        }
    }

    @ViewBuilder
    private var passwordManagerActions: some View {
        if layout.supportsCredentialFileImport, let space {
            ViewThatFits {
                HStack {
                    importButton(space: space)
                    Spacer()
                    selectionButton
                }
                VStack(alignment: .leading) {
                    importButton(space: space)
                    selectionButton
                }
            }

            if isSelectingCredentials {
                HStack {
                    Button("Select All") {
                        selectedCredentialIDs = Set(filteredDescriptors.map(\.id))
                    }
                    .disabled(filteredDescriptors.isEmpty)

                    Button("Delete Selected", role: .destructive) {
                        confirmsSelectionDeletion = true
                    }
                    .disabled(
                        selectedCredentialIDs.isEmpty
                            || credentials.isDeletingSelection
                    )
                }
            }
        }
    }

    private func importButton(space: SpaceModel) -> some View {
        Button("Import Passwords…") {
            isChoosingImportFile = true
        }
        .disabled(
            !space.settings.credentialPreferences.isEnabled
                || credentials.isPreparingImport
                || credentials.isCommittingImport
        )
        .accessibilityIdentifier("import-space-passwords")
    }

    private var selectionButton: some View {
        Button(isSelectingCredentials ? "Done" : "Select") {
            isSelectingCredentials.toggle()
            if !isSelectingCredentials { selectedCredentialIDs.removeAll() }
        }
        .disabled(credentials.descriptors.isEmpty || credentials.isDeletingSelection)
    }

    @ViewBuilder
    private func credentialPreferences(in space: SpaceModel) -> some View {
        Toggle(
            "Sync with iCloud Keychain",
            isOn: credentials.synchronizationBinding(
                in: space,
                accessController: spaceAccess
            )
        )
        .disabled(credentials.isChangingSynchronization)

        if credentials.isChangingSynchronization {
            ProgressView("Updating existing credentials…")
        }

        if browser.systemPasswordWriteThroughAvailability == .available {
            Toggle(
                "Offer a copy to Passwords",
                isOn: browser.credentialPreferenceBinding(
                    \.alsoOffersSaveToSystemPasswords,
                    in: space
                )
            )
        }
    }

    @ViewBuilder
    private var savedPasswords: some View {
        let descriptors = filteredDescriptors

        if credentials.isLoading {
            ProgressView("Reading this Space’s Keychain…")
                .frame(maxWidth: .infinity)
        } else if descriptors.isEmpty {
            // Passwords that can't be read have their own row, so the Space
            // isn't called empty above it.
            if !searchText.isEmpty || credentials.unreadableCount == 0 {
                Text(searchText.isEmpty ? "No saved passwords" : "No matches")
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(descriptors) { descriptor in
                BrowserPasswordDescriptorRow(
                    descriptor: descriptor,
                    space: space?.identity,
                    isDeleting: credentials.isDeleting(descriptor),
                    isSelectionActive: isSelectingCredentials,
                    isSelected: selectedCredentialIDs.contains(descriptor.id),
                    showDetails: {
                        guard let space,
                            let request = BrowserCredentialDetailRequest(
                                descriptor: descriptor,
                                space: space
                            )
                        else { return }
                        credentialDetailRequest = request
                    },
                    requestDeletion: { credentialPendingDeletion = descriptor },
                    toggleSelection: {
                        if !selectedCredentialIDs.insert(descriptor.id).inserted {
                            selectedCredentialIDs.remove(descriptor.id)
                        }
                    }
                )
            }
        }
    }

    private var unreadablePasswords: some View {
        HStack {
            Label(unreadablePasswordsLabel, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Remove…", role: .destructive) {
                confirmsUnreadableRemoval = true
            }
            .accessibilityIdentifier("remove-unreadable-passwords")
        }
    }

    // MARK: - Derived state

    private var space: SpaceModel? {
        guard let selectedSpaceID else { return nil }
        return browser.spaceModel(selectedSpaceID)
    }

    private var filteredDescriptors: [CredentialDescriptor] {
        credentials.descriptors(matching: searchText)
    }

    private var canRevealSelectedSpaceData: Bool {
        guard let space else { return false }
        return !spaceAccess.isLocked(space)
    }

    private var credentialLoadRequest: BrowserSettingsSpaceDataRequest {
        BrowserSettingsSpaceDataRequest(
            assignment: space.map(BrowserSpaceRuntimeAssignment.init(space:)),
            canRevealSpaceData: canRevealSelectedSpaceData
        )
    }

    private var passwordCountLabel: String {
        let count = credentials.descriptors.count
        return count == 1 ? "1 password" : "\(count) passwords"
    }

    private var deletionAlertIsPresented: Binding<Bool> {
        Binding {
            credentialPendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                credentialPendingDeletion = nil
            }
        }
    }

    private var importSummaryIsPresented: Binding<Bool> {
        Binding {
            credentials.importSummary != nil
        } set: { isPresented in
            if !isPresented { credentials.importSummary = nil }
        }
    }

    private var selectionDeletionMessage: String {
        let spaceName = space?.settings.name ?? "this Space"
        let count = selectedCredentialIDs.count
        let passwordLabel = count == 1 ? "password" : "passwords"
        return
            "Delete \(count) selected \(passwordLabel) from \(spaceName)? Crest will authenticate you and apply the deletion as one Keychain change. This cannot be undone."
    }

    private var unreadablePasswordsLabel: String {
        let count = credentials.unreadableCount
        return count == 1
            ? String(localized: "1 saved password can’t be read")
            : String(localized: "\(count) saved passwords can’t be read")
    }

    private var selectionDeletionButtonLabel: String {
        let count = selectedCredentialIDs.count
        return count == 1
            ? String(localized: "Delete 1 Password")
            : String(localized: "Delete \(count) Passwords")
    }

    private func prepareExport() {
        guard let selectedSpaceID, canRevealSelectedSpaceData else { return }
        Task { @MainActor in
            isExporting = await credentials.prepareExport(
                in: selectedSpaceID,
                accessController: spaceAccess
            ) {
                self.selectedSpaceID == selectedSpaceID
                    && self.canRevealSelectedSpaceData
            }
        }
    }

    private func clearSensitivePresentation() {
        credentialPendingDeletion = nil
        credentialDetailRequest = nil
        confirmsPlaintextExport = false
        isExporting = false
        isChoosingImportFile = false
        isSelectingCredentials = false
        selectedCredentialIDs.removeAll()
        confirmsSelectionDeletion = false
        confirmsUnreadableRemoval = false
        credentials.clearSensitiveData()
    }

    private func openImportResult(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result,
            let url = urls.first,
            let selectedSpaceID
        else {
            if case .failure = result {
                credentials.errorMessage = "Crest couldn’t open that password file."
            }
            return
        }
        Task { @MainActor in
            await credentials.prepareImport(
                from: url,
                in: selectedSpaceID,
                accessController: spaceAccess
            ) {
                self.selectedSpaceID == selectedSpaceID
                    && self.canRevealSelectedSpaceData
            }
        }
    }

    private func deleteSelectedCredentials() {
        guard let selectedSpaceID else { return }
        let ids = selectedCredentialIDs
        Task { @MainActor in
            if await credentials.deleteSelection(
                ids,
                in: selectedSpaceID,
                accessController: spaceAccess,
                isStillSelected: {
                    self.selectedSpaceID == selectedSpaceID
                        && self.canRevealSelectedSpaceData
                }
            ) {
                selectedCredentialIDs.removeAll()
                isSelectingCredentials = false
            }
        }
    }
}
