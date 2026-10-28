import SwiftUI

/// The matched-geometry pairing that grows a shell's address field into the
/// start page's palette.
///
/// Only a shell that animates the two as one control supplies this; the others
/// leave it absent and the palette simply appears in place.
struct BrowserStartPagePromotion {
    let namespace: Namespace.ID
    let id: String
}
