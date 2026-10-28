import SwiftUI

/// Clearing what a Space browsed within a time range: its history, the sites'
/// cookies and storage, and the cache, chosen by category. Other Spaces,
/// passwords, extensions, downloads and permissions stay.
struct BrowserClearBrowsingDataSection: View {
    let browser: BrowserStore
    let space: SpaceModel
    /// Lists the Space's sites again once their data may have gone.
    let didClear: () -> Void

    @State private var range = BrowsingDataRange.lastHour
    @State private var categories = Set(BrowsingDataCategory.all)
    @State private var confirmsClear = false
    @State private var isClearing = false
    @State private var outcome: Outcome?

    var body: some View {
        Section("Clear browsing data") {
            Picker("Time range", selection: $range) {
                ForEach(BrowsingDataRange.all, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            ForEach(BrowsingDataCategory.all, id: \.self) { category in
                Toggle(isOn: chosen(category)) {
                    Text(category.title)
                    if let detail = category.detail {
                        Text(detail)
                    }
                }
            }
            HStack {
                Label(outcome?.title ?? "Cleared", systemImage: outcome?.symbol ?? "checkmark")
                    .font(CrestTypography.metadata)
                    .foregroundStyle(CrestColor.textSecondary)
                    .opacity(outcome == nil ? 0 : 1)
                    .accessibilityHidden(outcome == nil)
                Spacer()
                Button("Clear…", role: .destructive) { confirmsClear = true }
                    .disabled(categories.isEmpty || isClearing)
            }
        }
        .confirmationDialog(
            "Clear browsing data in “\(space.settings.name)”?", isPresented: $confirmsClear, titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                Task { await clear() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(Text(range.title)): \(chosenTitles). Other Spaces aren’t affected.")
        }
        .onChange(of: range) { outcome = nil }
        .onChange(of: categories) { outcome = nil }
    }

    private var chosenTitles: String {
        BrowsingDataCategory.all.filter(categories.contains).map { String(localized: $0.title) }
            .formatted(.list(type: .and))
    }

    private func chosen(_ category: BrowsingDataCategory) -> Binding<Bool> {
        Binding {
            categories.contains(category)
        } set: { isOn in
            if isOn { categories.insert(category) } else { categories.remove(category) }
        }
    }

    /// Clears the chosen categories: the core clears the Space's history, and
    /// every engine what it keeps for the Space's profile.
    private func clear() async {
        let chosen = BrowsingDataCategory.all.filter(categories.contains)
        guard !chosen.isEmpty, !isClearing else { return }
        isClearing = true
        var cleared = true
        if chosen.contains(where: \.clearsHistory) {
            cleared = browser.clearHistory(in: space.id, range: range)
        }
        let erased = await browser.core.deleteData(
            DeleteBrowsingData(
                requestID: UUID(), profileID: space.profileID, ephemeral: browser.isPrivateBrowsing, range: range,
                categories: chosen))
        outcome = cleared && erased ? .cleared : .failed
        isClearing = false
        didClear()
    }
}

extension BrowserClearBrowsingDataSection {
    /// How the last clear went, which the section shows beside its button.
    fileprivate struct Outcome {
        static let cleared = Outcome(title: "Cleared", symbol: "checkmark")
        static let failed = Outcome(title: "Couldn’t clear everything", symbol: "exclamationmark.triangle")

        let title: LocalizedStringResource
        let symbol: String
    }
}
