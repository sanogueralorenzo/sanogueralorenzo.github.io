import AppKit
import SwiftUI

struct MinutesView: View {
    @ObservedObject var model: MinutesModel
    @State private var query = ""
    @State private var transcript: String?
    @State private var deleting: UUID?
    private var filtered: [Meeting] { model.meetings.filter { query.isEmpty || ($0.title + " " + $0.body).localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if model.activity.showsProgress { ProgressView().controlSize(.small) }
                else { Image(systemName: model.activity.recordingID == nil ? "waveform" : "record.circle.fill").foregroundStyle(model.activity.recordingID == nil ? Color.secondary : Color.red) }
                Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button(model.activity.recordingID == nil ? "Record" : "Stop", action: model.toggle)
                    .disabled(model.activity.showsProgress || model.requestingPermissions)
                    .help("Start or stop recording · ⌥⇧M")
                Menu("Provider") {
                    Picker("Provider", selection: Binding(get: { model.provider }, set: { if let provider = $0 { model.selectProvider(provider) } })) {
                        ForEach(Provider.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }
                    Divider()
                    Text("Transcripts are sent through Pi. Transcription stays local.")
                }.fixedSize().disabled(model.isWorking)

            }.padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            HSplitView {
                VStack(spacing: 8) {
                    SearchField(text: $query).padding(.horizontal, 10).padding(.top, 10)
                    if filtered.isEmpty {
                        Spacer()
                        Text(query.isEmpty ? "Your meetings, distilled." : "No matching meetings")
                            .font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
                        if query.isEmpty { Text("⌥⇧M starts and stops recording.").font(.system(size: 11)).foregroundStyle(.secondary) }
                        Spacer()
                    } else {
                        List(selection: $model.selected) {
                            ForEach(filtered) { meeting in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meeting.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                    HStack(spacing: 4) {
                                        Text(meeting.date.formatted(date: .abbreviated, time: .omitted))
                                        Text("·")
                                        Text(meeting.state == "ready" ? Meeting.elapsed(meeting.duration) : meeting.state.capitalized)
                                            .foregroundStyle(meeting.state == "failed" ? Color.orange : Color.secondary)
                                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                                }.padding(.vertical, 5).tag(meeting.id)
                            }
                        }.listStyle(.sidebar)
                    }
                }.frame(minWidth: 210, idealWidth: 225, maxWidth: 270)
                if let meeting = model.selectedMeeting {
                    detail(meeting).frame(minWidth: 370, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "text.page").font(.system(size: 28)).foregroundStyle(.tertiary)
                        Text("Leave with the outcome.").font(.system(size: 17, weight: .medium))
                        Text("Recap, decisions, next steps.\nYour full transcript stays one click away.")
                            .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(minWidth: 370, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let message = model.permissionMessage {
                Divider()
                HStack(alignment: .top) {
                    Text(message).font(.system(size: 12)).textSelection(.enabled)
                    Spacer()
                    Button("Grant Permissions", action: model.grantPermissions)
                        .disabled(model.isWorking || model.requestingPermissions)
                }.padding(12).background(Color.orange.opacity(0.08))
            }
            if let error = model.error {
                Divider()
                HStack(alignment: .top) {
                    Text(error).font(.system(size: 12)).textSelection(.enabled)
                    Spacer()
                    Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.padding(12).background(Color.orange.opacity(0.08))
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .sheet(isPresented: Binding(get: { transcript != nil }, set: { if !$0 { transcript = nil } })) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Full transcript").font(.headline); Spacer(); Button("Done") { transcript = nil }.keyboardShortcut(.cancelAction) }
                Text("Microphone and System identify audio sources, not individual speakers.").font(.caption).foregroundStyle(.secondary)
                ScrollView { Text(transcript ?? "").font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(20).frame(width: 620, height: 470)
        }
        .alert("Delete this meeting?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) { if let deleting { model.delete(deleting) }; deleting = nil }
        } message: { Text("The note, transcript, and recordings will be permanently removed from this Mac.") }
    }
    @ViewBuilder private func detail(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Meeting title", text: Binding(get: { model.meetings.first { $0.id == meeting.id }?.title ?? "" }, set: { model.edit(meeting.id, title: $0) }))
                .textFieldStyle(.plain).font(.system(size: 23, weight: .semibold)).padding(.bottom, 6)
                .disabled(meeting.state != "ready")
            Text(meeting.metadata).font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 16)
            if let warning = meeting.warning { Text(warning).font(.caption).foregroundStyle(.orange).padding(.bottom, 10) }
            if meeting.state == "ready" {
                NoteEditor(text: Binding(get: { model.meetings.first { $0.id == meeting.id }?.body ?? "" }, set: { model.edit(meeting.id, body: $0) })).id(meeting.id)
                HStack(spacing: 10) {
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(meeting.copied, forType: .string) }
                    Button("View transcript") { transcript = model.transcript(meeting.id) ?? "Transcript file is missing. Open saved files to inspect this meeting." }
                    Spacer()
                    Text("Saved automatically").font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(.top, 12)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if meeting.state == "processing" {
                        Text(model.status).font(.system(size: 14, weight: .medium))
                        Text("You can close this window. Minutes will notify you when the note is ready.").foregroundStyle(.secondary)
                    } else if meeting.state == "recording" {
                        Text("Capturing microphone and system audio").fontWeight(.medium)
                        Text("Transcription starts after you stop.").foregroundStyle(.secondary)
                    } else {
                        Text("This meeting needs attention").fontWeight(.medium)
                        Text(meeting.error ?? "Ready to process saved audio.").textSelection(.enabled)
                        Text("Your recordings and any transcript are saved.").foregroundStyle(.secondary)
                        HStack {
                            Button("Retry") { model.run(meeting.id) }.disabled(model.isWorking)
                            if model.transcript(meeting.id) != nil { Button("View transcript") { transcript = model.transcript(meeting.id) } }
                        }
                    }
                }.font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
            HStack {
                Text(meeting.processor ?? "").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Menu {
                    if meeting.state == "ready" { Button("Export note…") { model.export(meeting.id) } }
                    Button("Open saved files") { model.reveal(meeting.id) }
                    Button("Delete meeting…", role: .destructive) { deleting = meeting.id }.disabled(model.activity.meetingID == meeting.id)
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help("Meeting actions")
            }.padding(.top, 12)
        }.padding(22)
    }
}

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(); field.placeholderString = "Search meetings"; field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true; field.setAccessibilityLabel("Search meetings")
        return field
    }
    func updateNSView(_ view: NSSearchField, context: Context) { if view.stringValue != text { view.stringValue = text } }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) { parent.text = (obj.object as? NSSearchField)?.stringValue ?? "" }
    }
}

final class NoteTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let value = string as NSString
        if index < value.length {
            let line = value.lineRange(for: NSRange(location: index, length: 0))
            let prefix = value.substring(with: NSRange(location: line.location, length: min(1, line.length)))
            if ["☐", "☑"].contains(prefix), index <= line.location + 1 {
                let range = NSRange(location: line.location, length: 1)
                if shouldChangeText(in: range, replacementString: prefix == "☐" ? "☑" : "☐") {
                    textStorage?.replaceCharacters(in: range, with: prefix == "☐" ? "☑" : "☐"); didChangeText()
                }
                return
            }
        }
        super.mouseDown(with: event)
    }
}
struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let view = NoteTextView()
        view.isRichText = false; view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false; view.isContinuousSpellCheckingEnabled = true
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 0, height: 3)
        view.textContainer?.lineFragmentPadding = 0
        view.drawsBackground = false; view.allowsUndo = true; view.delegate = context.coordinator
        view.setAccessibilityLabel("Meeting note, editable and saved automatically")
        view.string = text; context.coordinator.style(view)
        let scroll = NSScrollView(); scroll.documentView = view; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text; context.coordinator.style(view) }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        init(_ parent: NoteEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string; style(view)
        }
        func style(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4; paragraph.paragraphSpacing = 5
            storage.beginEditing()
            storage.setAttributes([.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph], range: NSRange(location: 0, length: storage.length))
            let text = view.string as NSString
            text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byParagraphs) { value, range, _, _ in
                if ["Decisions", "Action items", "Open questions"].contains(value ?? "") {
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 12, weight: .semibold), range: range)
                }
            }
            storage.endEditing()
            view.typingAttributes = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        }
    }
}
