import SwiftUI

extension Animation {

    func unlessReducingMotion(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : self
    }
}
