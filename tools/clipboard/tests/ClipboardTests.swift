import Foundation

@main
@MainActor
enum ClipboardTests {
    static func main() async throws {
        try ClipboardHistoryTests.run()
        try ClipboardFormatsTests.run()
        try await ClipboardWebsiteIconsTests.run()
    }
}
