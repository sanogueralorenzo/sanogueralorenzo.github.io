import WebKit

extension SiteOrigin {
    /// The origin WebKit reports for a frame. WebKit spells a URL's default
    /// port as 0, which the normalizing initializer turns into the scheme's
    /// default, so the origin equals the one made from the frame's URL.
    @MainActor
    init(_ origin: WKSecurityOrigin) {
        self.init(scheme: origin.protocol, host: origin.host, port: origin.port)
    }
}
