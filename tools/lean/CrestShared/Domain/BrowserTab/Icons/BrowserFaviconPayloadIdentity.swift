import CryptoKit
import Foundation

/// A fixed-size stand-in for a favicon's bytes.
///
/// SwiftUI evaluates `.task` identities and compares view values *during view
/// updates*, on the main actor, once per visible tab row. An identity that holds
/// the payload itself therefore hashes and memcmps a whole image buffer on every
/// update; an identity that samples a few fixed offsets is constant work but can
/// alias two genuinely different icons. Neither is acceptable, so the work happens
/// exactly once, where the payload is stored: `FaviconAssets` fingerprints a tab's
/// image when the bytes are set, and the render path compares digests for the rest
/// of the payload's life.
///
/// The digest reads every byte exactly once and carries the payload's length in its
/// own padding, so distinct icons cannot alias and no separate byte count is needed.
/// It is never stored or synchronized: it is recomputed whenever the bytes are set.
struct BrowserFaviconPayloadIdentity: Hashable, Sendable {
    private let digest: SHA256Digest

    init(hashing payload: Data) {
        digest = SHA256.hash(data: payload)
    }
}
