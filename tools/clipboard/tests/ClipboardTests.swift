import Foundation

@main
@MainActor
enum ClipboardTests {
    static func main() throws {
        try ClipboardHistoryTests.run()
        try ClipboardFormatsTests.run()
        #if UI_TESTS
        ClipboardSearchTests.run()
        #endif
    }
}
