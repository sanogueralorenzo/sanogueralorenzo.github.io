extension MemoryPressureLevel: Comparable {
    // MARK: - Actions - Ordering

    /// Ordered by severity, so an escalation is `critical > warning`.
    static func < (lhs: MemoryPressureLevel, rhs: MemoryPressureLevel) -> Bool {
        lhs.severity < rhs.severity
    }
}
