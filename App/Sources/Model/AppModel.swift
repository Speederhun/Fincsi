import Foundation
import Observation
import FincsiKit

enum SyncState: Equatable {
    case idle
    case running
    case finished(String)
    case failed(String)
}

struct RecipeFilter: Equatable {
    var query: String = ""
    var course: Course? = nil
    var favoritesOnly = false
    /// Igaz: csak a kamra alapján javasolt receptek; hamis: az összes használható.
    var pantryMode = true
}

/// Az app központi állapota. A felület ezt figyeli; a tartós adatok a `UserData`-ban vannak.
@MainActor
@Observable
final class AppModel {
    struct Core {
        let catalog: IngredientCatalog
        let engine: MatchEngine
        let bundled: [Recipe]
    }

    private(set) var core: Core?
    private(set) var bootError: String?

    private(set) var data = UserData()
    private(set) var remote: [Recipe] = []
    private(set) var matches: [RecipeMatch] = []
    private(set) var lastSync: Date?

    var syncState: SyncState = .idle
    var translating: Set<String> = []
    /// Rövid, a felületen megjelenő üzenet (hiba vagy visszajelzés).
    var banner: String?

    private(set) var deepLKey: String

    func setDeepLKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        deepLKey = trimmed
        Keychain.write(trimmed, account: "deepl")
    }

    private let userStore: JSONFileStore<UserData>
    private let recipeStore: RecipeStore
    private let http: HTTPClient = URLSessionHTTPClient()
    private var saveTask: Task<Void, Never>?
    private var recipeIndex: [String: Recipe] = [:]

    init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Fincsi", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        userStore = JSONFileStore<UserData>(url: directory.appendingPathComponent("user.json"))
        recipeStore = RecipeStore(directory: directory)
        deepLKey = Keychain.read("deepl")
        data = userStore.load() ?? UserData()

        do {
            let catalog = try IngredientCatalog.loadBundled()
            let table = try SubstitutionTable.loadBundled()
            let bundled = try BundledRecipes.load(catalog: catalog)
            core = Core(catalog: catalog, engine: MatchEngine(catalog: catalog, substitutions: table),
                        bundled: bundled)
        } catch {
            bootError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        rebuild()
        Task { await self.loadRemote() }
    }

    // MARK: - Adatok

    var catalog: IngredientCatalog? { core?.catalog }

    var allRecipes: [Recipe] { (core?.bundled ?? []) + remote }

    func recipe(id: String) -> Recipe? { recipeIndex[id] }

    func match(id: String) -> RecipeMatch? {
        matches.first { $0.recipe.id == id }
    }

    /// Módosítja a felhasználói adatokat, menti és újraszámolja az ajánlásokat.
    func update(_ change: (inout UserData) -> Void) {
        var copy = data
        change(&copy)
        guard copy != data else { return }
        let recompute = copy.profile != data.profile
        data = copy
        if recompute { rebuild() }
        scheduleSave()
    }

    private func rebuild() {
        guard let core = core else { return }
        let all = allRecipes
        recipeIndex = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        matches = core.engine.ranked(core.engine.evaluateAll(all, profile: data.profile))
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = data
        let store = userStore
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            do {
                try store.save(snapshot)
            } catch {
                self?.banner = (error as? LocalizedError)?.errorDescription
            }
        }
    }

    /// Azonnali mentés (pl. háttérbe lépéskor).
    func saveNow() {
        saveTask?.cancel()
        do {
            try userStore.save(data)
        } catch {
            banner = (error as? LocalizedError)?.errorDescription
        }
    }

    // MARK: - Letöltött receptek

    private func loadRemote() async {
        remote = await recipeStore.displayRecipes()
        lastSync = await recipeStore.lastSync
        rebuild()
    }

    var remoteCount: Int { remote.count }

    func syncRecipes() async {
        guard let core = core, syncState != .running else { return }
        syncState = .running
        let client = MealDBClient(http: http, apiKey: data.settings.mealDBKey)
        do {
            let report = try await recipeStore.sync(client: client, mapper: MealDBMapper(catalog: core.catalog))
            await loadRemote()
            if report.failedLetters > 0 {
                syncState = .finished("\(report.total) recept van meg; \(report.failedLetters) betű letöltése nem sikerült, próbáld újra.")
            } else {
                syncState = .finished("Kész: \(report.total) letöltött recept (\(report.added) új).")
            }
        } catch {
            syncState = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func clearDownloaded() async {
        do {
            try await recipeStore.clearRemote()
            try await recipeStore.clearTranslations()
        } catch {
            banner = (error as? LocalizedError)?.errorDescription
        }
        await loadRemote()
        syncState = .idle
    }

    // MARK: - Fordítás

    private func makeTranslator() -> RecipeTranslator {
        var list: [TextTranslator] = []
        if !deepLKey.isEmpty {
            list.append(DeepLTranslator(http: http, apiKey: deepLKey))
        }
        list.append(MyMemoryTranslator(http: http, email: data.settings.myMemoryEmail))
        return RecipeTranslator(translators: list)
    }

    func translate(_ recipeID: String) async {
        guard let recipe = remote.first(where: { $0.id == recipeID }), recipe.needsTranslation,
              !translating.contains(recipeID) else { return }
        // A `remote` már fordított receptet tartalmazhat; az eredeti angol szöveg a tárolóból jön.
        translating.insert(recipeID)
        defer { translating.remove(recipeID) }
        do {
            let stored = await recipeStore.remoteRecipes
            let original = stored.first(where: { $0.id == recipeID }) ?? recipe
            let translated = try await makeTranslator().translate(original)
            try await recipeStore.saveTranslation(translated)
            await loadRemote()
        } catch is CancellationError {
            return
        } catch {
            banner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Gyakori műveletek

    func addMissingToShopping(_ match: RecipeMatch, scale: Double) {
        let title = match.recipe.title
        update { data in
            for evaluation in match.missing {
                let ingredient = evaluation.ingredient
                data.addToShopping(ingredientID: evaluation.effectiveID, name: evaluation.effectiveName,
                                   amount: ingredient.amount.map { $0 * scale }, unit: ingredient.unit,
                                   recipeTitle: title)
            }
        }
    }

    func markCooked(_ recipe: Recipe) {
        update { $0.markCooked(recipeID: recipe.id, title: recipe.title) }
    }

    func resetAllData() {
        update { data in
            let key = data.settings
            data = UserData()
            data.settings = key
            data.onboardingDone = true
        }
    }
}
