extension String? {
    /// The component as it crosses to the core: an empty component crosses as
    /// `nil`, as a missing one does.
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
