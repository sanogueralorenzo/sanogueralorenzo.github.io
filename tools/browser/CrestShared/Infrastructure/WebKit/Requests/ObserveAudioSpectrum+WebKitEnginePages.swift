import Foundation

extension ObserveAudioSpectrum {
    /// WebKit measures no page's sound, so it never starts.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        false
    }
}
