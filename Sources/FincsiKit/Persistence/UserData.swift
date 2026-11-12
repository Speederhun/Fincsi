import Foundation

public struct ShoppingItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Katalógus-azonosító, ha ismert.
    public var ingredientID: String?
    public var name: String
    public var amount: Double?
    public var unit: String
    public var checked: Bool
    public var recipeTitles: [String]

    public init(id: UUID = UUID(), ingredientID: String?, name: String, amount: Double? = nil, unit: String = "",
                checked: Bool = false, recipeTitles: [String] = []) {
        self.id = id
        self.ingredientID = ingredientID
        self.name = name
        self.amount = amount
        self.unit = unit
        self.checked = checked
        self.recipeTitles = recipeTitles
    }
}

public struct HistoryEntry: Codable, Hashable, Sendable {
    public var recipeID: String
    public var title: String
    public var date: Date

    public init(recipeID: String, title: String, date: Date = Date()) {
        self.recipeID = recipeID
        self.title = title
        self.date = date
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var assumeStaples: Bool = true
    public var allowUncertain: Bool = false
    /// Legfeljebb ennyi hiányzó alapanyagnál kerül a „majdnem megvan” listába.
    public var maxMissing: Int = 3
    public var autoTranslate: Bool = false
    public var mealDBKey: String = ""
    public var myMemoryEmail: String = ""

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        assumeStaples = try container.decodeIfPresent(Bool.self, forKey: .assumeStaples) ?? defaults.assumeStaples
        allowUncertain = try container.decodeIfPresent(Bool.self, forKey: .allowUncertain) ?? defaults.allowUncertain
        maxMissing = try container.decodeIfPresent(Int.self, forKey: .maxMissing) ?? defaults.maxMissing
        autoTranslate = try container.decodeIfPresent(Bool.self, forKey: .autoTranslate) ?? defaults.autoTranslate
        mealDBKey = try container.decodeIfPresent(String.self, forKey: .mealDBKey) ?? defaults.mealDBKey
        myMemoryEmail = try container.decodeIfPresent(String.self, forKey: .myMemoryEmail) ?? defaults.myMemoryEmail
    }
}

/// Minden, amit az app a felhasználóhoz kötve ment.
public struct UserData: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var pantry: Set<String> = []
    public var excluded: Set<String> = []
    public var diets: Set<Diet> = []
    public var favorites: [String] = []
    public var shopping: [ShoppingItem] = []
    public var history: [HistoryEntry] = []
    public var settings = AppSettings()
    public var onboardingDone: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        pantry = try container.decodeIfPresent(Set<String>.self, forKey: .pantry) ?? []
        excluded = try container.decodeIfPresent(Set<String>.self, forKey: .excluded) ?? []
        // Ismeretlen étrend (újabb verzióból) ne okozzon hibát.
        let dietNames = try container.decodeIfPresent([String].self, forKey: .diets) ?? []
        diets = Set(dietNames.compactMap { Diet(rawValue: $0) })
        favorites = try container.decodeIfPresent([String].self, forKey: .favorites) ?? []
        shopping = try container.decodeIfPresent([ShoppingItem].self, forKey: .shopping) ?? []
        history = try container.decodeIfPresent([HistoryEntry].self, forKey: .history) ?? []
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        onboardingDone = try container.decodeIfPresent(Bool.self, forKey: .onboardingDone) ?? false
    }

    public var profile: UserProfile {
        UserProfile(pantry: pantry, excluded: excluded, diets: diets,
                    assumeStaples: settings.assumeStaples, allowUncertain: settings.allowUncertain)
    }

    // MARK: Kedvencek

    public func isFavorite(_ recipeID: String) -> Bool { favorites.contains(recipeID) }

    public mutating func toggleFavorite(_ recipeID: String) {
        if let index = favorites.firstIndex(of: recipeID) {
            favorites.remove(at: index)
        } else {
            favorites.insert(recipeID, at: 0)
        }
    }

    // MARK: Kamra

    /// Az alapanyag kamrába tétele; kizárt alapanyagot nem lehet egyszerre kamrában tartani.
    public mutating func setInPantry(_ id: String, _ inPantry: Bool) {
        if inPantry {
            pantry.insert(id)
            excluded.remove(id)
        } else {
            pantry.remove(id)
        }
    }

    public mutating func setExcluded(_ id: String, _ isExcluded: Bool) {
        if isExcluded {
            excluded.insert(id)
            pantry.remove(id)
        } else {
            excluded.remove(id)
        }
    }

    // MARK: Bevásárlólista

    /// Hozzáad egy tételt; azonos alapanyag és mértékegység esetén összevonja a mennyiséget.
    public mutating func addToShopping(ingredientID: String?, name: String, amount: Double?, unit: String,
                                       recipeTitle: String?) {
        let title = recipeTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = shopping.firstIndex(where: { item in
            guard !item.checked else { return false }
            if let id = ingredientID, let other = item.ingredientID {
                return id == other && item.unit == unit
            }
            return item.ingredientID == nil && ingredientID == nil
                && item.name.lowercased() == name.lowercased() && item.unit == unit
        }) {
            switch (shopping[index].amount, amount) {
            case let (existing?, added?):
                shopping[index].amount = existing + added
            case (nil, let added?):
                shopping[index].amount = added
            default:
                break
            }
            if let title = title, !title.isEmpty, !shopping[index].recipeTitles.contains(title) {
                shopping[index].recipeTitles.append(title)
            }
            return
        }
        shopping.append(ShoppingItem(ingredientID: ingredientID, name: name, amount: amount, unit: unit,
                                     recipeTitles: (title?.isEmpty == false) ? [title!] : []))
    }

    public mutating func removeShopping(ids: Set<UUID>) {
        shopping.removeAll { ids.contains($0.id) }
    }

    public mutating func clearCheckedShopping() {
        shopping.removeAll { $0.checked }
    }

    /// A kipipált tételeket a kamrába teszi, majd törli a listáról. Visszaadja, hány tétel került át.
    @discardableResult
    public mutating func moveCheckedToPantry() -> Int {
        var moved = 0
        for item in shopping where item.checked {
            if let id = item.ingredientID {
                setInPantry(id, true)
                moved += 1
            }
        }
        shopping.removeAll { $0.checked }
        return moved
    }

    // MARK: Előzmények

    public mutating func markCooked(recipeID: String, title: String, date: Date = Date(), limit: Int = 100) {
        history.removeAll { $0.recipeID == recipeID }
        history.insert(HistoryEntry(recipeID: recipeID, title: title, date: date), at: 0)
        if history.count > limit {
            history = Array(history.prefix(limit))
        }
    }
}
