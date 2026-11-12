import Foundation

struct RemoteRecipeFile: Codable {
    var version: Int = 1
    var fetchedAt: Date?
    var recipes: [Recipe] = []
}

struct TranslationFile: Codable {
    var version: Int = 1
    var items: [String: TranslatedRecipe] = [:]
}

/// A letöltött (TheMealDB) receptek és a lefordított változatok helyi tárolója.
public actor RecipeStore {
    private let remoteStore: JSONFileStore<RemoteRecipeFile>
    private let translationStore: JSONFileStore<TranslationFile>
    private var remote: RemoteRecipeFile
    private var translations: TranslationFile

    public init(directory: URL) {
        remoteStore = JSONFileStore(url: directory.appendingPathComponent("remote_recipes.json"))
        translationStore = JSONFileStore(url: directory.appendingPathComponent("translations.json"))
        remote = remoteStore.load() ?? RemoteRecipeFile()
        translations = translationStore.load() ?? TranslationFile()
    }

    public var remoteRecipes: [Recipe] { remote.recipes }
    public var lastSync: Date? { remote.fetchedAt }

    /// A letöltött receptek, a mentett fordítással kiegészítve.
    public func displayRecipes() -> [Recipe] {
        remote.recipes.map { recipe in
            if let translation = translations.items[recipe.id] {
                return recipe.applying(translation)
            }
            return recipe
        }
    }

    public func translation(for recipeID: String) -> TranslatedRecipe? {
        translations.items[recipeID]
    }

    public func saveTranslation(_ translation: TranslatedRecipe) throws {
        translations.items[translation.recipeID] = translation
        try translationStore.save(translations)
    }

    public func clearTranslations() throws {
        translations = TranslationFile()
        try translationStore.save(translations)
    }

    public struct SyncReport: Sendable, Equatable {
        public let total: Int
        public let added: Int
        public let failedLetters: Int
        public let error: FincsiError?
    }

    /// Letöltés és összefésülés. Ha egyes betűk hibáznak, a korábbi receptek megmaradnak.
    public func sync(client: MealDBClient, mapper: MealDBMapper) async throws -> SyncReport {
        let result = await client.fetchAll()
        if result.meals.isEmpty, result.failedLetters.count == MealDBClient.letters.count {
            throw result.lastError ?? FincsiError.network("")
        }
        var byID: [String: Recipe] = [:]
        for recipe in remote.recipes { byID[recipe.id] = recipe }
        let before = byID.count
        for raw in result.meals {
            if let recipe = mapper.recipe(from: raw) {
                byID[recipe.id] = recipe
            }
        }
        remote.recipes = byID.values.sorted { $0.id < $1.id }
        // Csak teljes siker esetén frissítjük a szinkron idejét.
        if result.failedLetters.isEmpty {
            remote.fetchedAt = Date()
        }
        try remoteStore.save(remote)
        return SyncReport(total: remote.recipes.count, added: remote.recipes.count - before,
                          failedLetters: result.failedLetters.count, error: result.lastError)
    }

    public func clearRemote() throws {
        remote = RemoteRecipeFile()
        try remoteStore.save(remote)
    }
}
