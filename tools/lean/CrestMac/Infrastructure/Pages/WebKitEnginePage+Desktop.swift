import Foundation

extension WebKitEnginePage {
    func makeDesktopAdapter() -> BrowserWebKitPageAdapter {
        BrowserWebKitPageAdapter(page: self)
    }
}
