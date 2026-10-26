import AppKit

extension BrowserPage: @preconcurrency NSSharingServicePickerDelegate {
    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        if sharingPicker === sharingServicePicker {
            sharingPicker = nil
        }
    }
}
