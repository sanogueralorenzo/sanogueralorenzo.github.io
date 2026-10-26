extension DevicePlatform {
    /// The device class this process runs on.
    static var current: DevicePlatform {
        #if os(macOS)
            .desktop
        #else
            .mobile
        #endif
    }
}
