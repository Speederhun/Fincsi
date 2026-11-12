import Foundation

private struct IngredientFile: Decodable {
    let version: Int
    let categories: [IngredientCategory]
    let ingredients: [Ingredient]
}

/// Az alapanyagok katalógusa: keresés (ékezetfüggetlen), angol nevek feloldása, család-kapcsolatok.
public struct IngredientCatalog: Sendable {
    public let categories: [IngredientCategory]
    public let ingredients: [Ingredient]

    private let byID: [String: Ingredient]
    private let englishIndex: [String: String]
    private let searchEntries: [SearchEntry]

    private struct SearchEntry: Sendable {
        let id: String
        let nameKey: String
        let aliasKeys: [String]
    }

    public init(categories: [IngredientCategory], ingredients: [Ingredient]) {
        self.categories = categories.sorted { $0.order < $1.order }
        self.ingredients = ingredients

        var map: [String: Ingredient] = [:]
        for item in ingredients {
            map[item.id] = item
        }
        self.byID = map

        var index: [String: String] = [:]
        // 1. menet: pontos aliasok
        for item in ingredients {
            for alias in item.aliasesEN {
                let key = NameNormalizer.light(alias)
                if !key.isEmpty && index[key] == nil {
                    index[key] = item.id
                }
            }
        }
        // 2. menet: egyes számú alakok, csak ha még szabad a kulcs
        for item in ingredients {
            for alias in item.aliasesEN {
                let key = NameNormalizer.singular(NameNormalizer.light(alias))
                if !key.isEmpty && index[key] == nil {
                    index[key] = item.id
                }
            }
        }
        self.englishIndex = index

        self.searchEntries = ingredients.map { item in
            SearchEntry(
                id: item.id,
                nameKey: TextFolding.fold(item.name),
                aliasKeys: item.aliasesHU.map { TextFolding.fold($0) }
            )
        }
    }

    // MARK: - Betöltés

    public static func loadBundled() throws -> IngredientCatalog {
        guard let url = Bundle.module.url(forResource: "ingredients", withExtension: "json") else {
            throw FincsiError.resourceMissing("ingredients.json")
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(IngredientFile.self, from: data)
        return IngredientCatalog(categories: file.categories, ingredients: file.ingredients)
    }

    // MARK: - Lekérdezés

    public subscript(id: String) -> Ingredient? {
        return byID[id]
    }

    public func name(of id: String) -> String {
        return byID[id]?.name ?? id
    }

    public func ingredients(in categoryID: String) -> [Ingredient] {
        let locale = Locale(identifier: "hu_HU")
        return ingredients
            .filter { $0.category == categoryID }
            .sorted { $0.name.compare($1.name, locale: locale) == .orderedAscending }
    }

    /// Egy alapanyag a „család” miatt is kielégíti az általánosabb igényt (pl. a mozzarella a „sajt”-ot).
    public func satisfies(pantryItem: String, requirement: String) -> Bool {
        if pantryItem == requirement { return true }
        if let family = byID[pantryItem]?.family, family == requirement { return true }
        return false
    }

    /// Kizárt-e az alapanyag a felhasználó „nem kérem” listája alapján (a családon keresztül is).
    public func isExcluded(_ id: String, by excluded: Set<String>) -> Bool {
        if excluded.isEmpty { return false }
        if excluded.contains(id) { return true }
        if let family = byID[id]?.family, excluded.contains(family) { return true }
        return false
    }

    /// Angol alapanyagnév feloldása katalógus-azonosítóra. Csak biztos egyezést ad vissza, tippelni nem tippel.
    public func resolve(englishName raw: String) -> String? {
        let light = NameNormalizer.light(raw)
        if light.isEmpty { return nil }
        var candidates = [light]
        let stripped = NameNormalizer.stripped(light)
        if !stripped.isEmpty && stripped != light {
            candidates.append(stripped)
        }
        for candidate in candidates {
            if let id = englishIndex[candidate] { return id }
        }
        for candidate in candidates {
            if let id = englishIndex[NameNormalizer.singular(candidate)] { return id }
        }
        return nil
    }

    // MARK: - Keresés

    /// Ékezet- és kisbetű-független keresés a magyar nevekben és aliasokban.
    public func search(_ query: String, limit: Int = 50) -> [Ingredient] {
        let folded = TextFolding.fold(query)
        if folded.isEmpty { return [] }
        let tokens = folded.split(separator: " ").map(String.init)

        var scored: [(score: Int, item: Ingredient)] = []
        for entry in searchEntries {
            guard let item = byID[entry.id] else { continue }
            var best = Int.max

            if let s = Self.score(key: entry.nameKey, query: folded, tokens: tokens) {
                best = min(best, s)
            }
            for alias in entry.aliasKeys {
                if let s = Self.score(key: alias, query: folded, tokens: tokens) {
                    best = min(best, s + 10)
                }
            }
            if best != Int.max {
                scored.append((best, item))
            }
        }

        let locale = Locale(identifier: "hu_HU")
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.item.name.count != rhs.item.name.count { return lhs.item.name.count < rhs.item.name.count }
            return lhs.item.name.compare(rhs.item.name, locale: locale) == .orderedAscending
        }
        return scored.prefix(limit).map { $0.item }
    }

    private static func score(key: String, query: String, tokens: [String]) -> Int? {
        if key == query { return 0 }
        if key.hasPrefix(query) { return 1 }
        let words = key.split(separator: " ").map(String.init)
        let allWordPrefix = tokens.allSatisfy { token in words.contains { $0.hasPrefix(token) } }
        if allWordPrefix { return 2 }
        let allContained = tokens.allSatisfy { key.contains($0) }
        if allContained { return 3 }
        return nil
    }
}
