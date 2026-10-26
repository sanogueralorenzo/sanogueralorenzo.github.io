import Foundation

/// Produces a high-entropy ASCII password without storing or logging it.
///
/// The portable core owns the recipe: the length and the character groups.
/// The password is drawn here from the system's secure random source, so the
/// secret never leaves the native layer that saves and fills it. One character
/// comes from every group, the rest from all groups, then the order is shuffled.
enum BrowserStrongPasswordGenerator {
    static func generate(from recipe: StrongPasswordRecipe) throws -> String {
        var generator = SystemRandomNumberGenerator()
        return try generate(from: recipe, using: &generator)
    }

    static func generate<Generator: RandomNumberGenerator>(
        from recipe: StrongPasswordRecipe,
        using generator: inout Generator
    ) throws -> String {
        let groups = recipe.groups.map(Array.init)
        guard !groups.isEmpty, groups.allSatisfy({ !$0.isEmpty }), recipe.length >= groups.count else {
            throw BrowserStrongPasswordGenerationError.unavailable
        }
        let allCharacters = groups.flatMap { $0 }
        var password = groups.map { characters in
            characters[Int.random(in: characters.indices, using: &generator)]
        }
        while password.count < recipe.length {
            password.append(
                allCharacters[Int.random(in: allCharacters.indices, using: &generator)]
            )
        }
        password.shuffle(using: &generator)
        return String(password)
    }
}
