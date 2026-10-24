import Foundation

extension Error {
    /// What the person is told of a failure: a rejection's own words, or
    /// `Rejection.unexplained` for one whose rule says nothing, and any
    /// other error's description.
    var personFacingDescription: String {
        (self as? Rejection)?.explanation ?? localizedDescription
    }
}
