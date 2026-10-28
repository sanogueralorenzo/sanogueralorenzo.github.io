extension SitePermissionRecordState {
    var displayLabel: String {
        let title = String(localized: permission.title)
        guard let detail, !detail.isEmpty else { return title }
        return "\(title) (\(detail))"
    }
}
