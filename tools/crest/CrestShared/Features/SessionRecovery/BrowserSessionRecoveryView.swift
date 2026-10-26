import SwiftUI

struct BrowserSessionRecoveryView<Value>: View {
    let launch: BrowserApplicationLaunch<Value>
    @State private var confirmsRestore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Crest couldn't open your session", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.title2.bold())
                Text(
                    "Your saved files are preserved. Browsing and iCloud sync will stay stopped until your session can be opened."
                )
                if launch.failure?.requiresNewerApp == true {
                    Text("This session was saved by a newer version of Crest. Update Crest before opening it.")
                } else if let date = launch.failure?.checkpointDate {
                    Text(
                        "A recovery checkpoint is available from \(date.formatted(date: .abbreviated, time: .shortened))."
                    )
                    Button("Restore Checkpoint") { confirmsRestore = true }
                        .accessibilityIdentifier("session-recovery-restore")
                } else {
                    Text(
                        "No recovery checkpoint is available. Retry after checking that your disk is available and has free space."
                    )
                }
                if let error = launch.recoveryError { Text(error).foregroundStyle(.red) }
                Button("Retry", action: launch.retry)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("session-recovery-retry")
                #if os(macOS)
                    if let directory = launch.failure?.storageDirectory {
                        Button("Show Saved Files") {
                            NSWorkspace.shared.open(directory)
                        }
                    }
                #endif
            }
            .frame(maxWidth: 500, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(
            "Restore the last checkpoint?", isPresented: $confirmsRestore,
            titleVisibility: .visible
        ) {
            Button("Restore Checkpoint", action: launch.restore)
        } message: {
            Text(
                "Changes made after this checkpoint may be missing. Crest will keep a separate copy of the current files and fetch current iCloud records before uploading again."
            )
        }
    }
}
