import SwiftUI

enum BrowserDataClearRange: TimeInterval, CaseIterable {
    case hour = 3600
    case day = 86400
    case week = 604800
    case allTime = 0

    var title: String {
        switch self {
        case .hour: "Last hour"
        case .day: "Last 24 hours"
        case .week: "Last 7 days"
        case .allTime: "All time"
        }
    }

    func cutoff(at now: Date) -> Date {
        self == .allTime ? .distantPast : now.addingTimeInterval(-rawValue)
    }
}

struct BrowserClearBrowsingData: View {
    let store: BrowserStore
    let target: BrowserBrowsingDataTarget
    @Environment(\.dismiss) private var dismiss
    @State private var range = BrowserDataClearRange.hour
    @State private var history = true
    @State private var websiteData = false
    @State private var cache = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clear Browsing Data").font(.headline)
                .accessibilityAddTraits(.isHeader)
            LabeledContent("Space", value: target.name)
            Picker("Time range", selection: $range) {
                ForEach(BrowserDataClearRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle("History", isOn: $history)
                Toggle("Logins and website data", isOn: $websiteData)
                Toggle("Cached images and files", isOn: $cache)
            }
            .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Clear", role: .destructive, action: clear)
                    .disabled(!history && !websiteData && !cache)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func clear() {
        let cutoff = range.cutoff(at: Date())
        let history = history
        let websiteData = websiteData
        let cache = cache
        dismiss()
        Task {
            await store.clearBrowsingData(
                in: target.id, since: cutoff, history: history, websiteData: websiteData, cache: cache)
        }
    }
}
