import Foundation

/// Does what the save prompt's prominent button asks: one method per
/// `BrowserCredentialPromptPrimaryAction`, each run with the prompt's own code.
@MainActor
protocol BrowserCredentialPromptPerformer {
    /// Saves or updates the password.
    func save()

    /// Checks the saved passwords again after the check failed.
    func retryPreparation()

    /// Offers the password to the system's Passwords app again after the
    /// offer failed.
    func retrySystemPasswords()
}
