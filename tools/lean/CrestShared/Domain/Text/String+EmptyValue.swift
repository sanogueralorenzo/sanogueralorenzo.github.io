extension String {
    /// Treats only an empty value as absent; whitespace remains unchanged.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
