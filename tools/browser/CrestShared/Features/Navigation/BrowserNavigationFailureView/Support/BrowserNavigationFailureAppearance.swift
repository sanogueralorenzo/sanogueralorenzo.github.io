enum BrowserNavigationFailureAppearance {
    static func brandColor(
        for branding: SpaceBranding?
    ) -> BrandColor? {
        branding?.primaryColor
    }
}
