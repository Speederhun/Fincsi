import Foundation

public enum Course: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case leves
    case fozelek
    case foetel
    case tesztaetel
    case koret
    case desszert
    case reggeli
    case egyeb

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .leves: return "Leves"
        case .fozelek: return "Főzelék"
        case .foetel: return "Főétel"
        case .tesztaetel: return "Tésztaétel"
        case .koret: return "Köret, saláta"
        case .desszert: return "Desszert"
        case .reggeli: return "Reggeli"
        case .egyeb: return "Egyéb"
        }
    }
}

public enum RecipeSource: String, Codable, Hashable, Sendable {
    /// Az appba beépített, magyar nyelvű recept.
    case bundled
    /// Az interneten, TheMealDB-ből letöltött recept.
    case mealdb
}

public struct RecipeIngredient: Codable, Hashable, Sendable {
    /// Katalógus-azonosító; `nil`, ha a név nem azonosítható (ilyenkor az étrendi szűrés nem tud dönteni).
    public var ingredientID: String?
    public var name: String
    public var amount: Double?
    public var unit: String
    public var note: String?
    public var optional: Bool
    /// Az eredeti mérték szövege, ha nem sikerült számmá alakítani.
    public var rawMeasure: String?

    public init(ingredientID: String?, name: String, amount: Double? = nil, unit: String = "",
                note: String? = nil, optional: Bool = false, rawMeasure: String? = nil) {
        self.ingredientID = ingredientID
        self.name = name
        self.amount = amount
        self.unit = unit
        self.note = note
        self.optional = optional
        self.rawMeasure = rawMeasure
    }
}

public struct RecipeStep: Codable, Hashable, Sendable {
    public var text: String
    public var timerMinutes: Int?

    public init(text: String, timerMinutes: Int? = nil) {
        self.text = text
        self.timerMinutes = timerMinutes
    }
}

public struct Recipe: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var source: RecipeSource
    public var title: String
    public var summary: String
    public var course: Course
    public var servings: Int
    public var prepMinutes: Int
    public var cookMinutes: Int
    public var tags: [String]
    public var imageURL: URL?
    public var sourceURL: URL?
    public var ingredients: [RecipeIngredient]
    public var steps: [RecipeStep]
    /// „hu” a beépített, „en” a letöltött (fordításra váró) receptek nyelve.
    public var language: String

    public init(id: String, source: RecipeSource, title: String, summary: String = "", course: Course = .egyeb,
                servings: Int = 4, prepMinutes: Int = 0, cookMinutes: Int = 0, tags: [String] = [],
                imageURL: URL? = nil, sourceURL: URL? = nil, ingredients: [RecipeIngredient] = [],
                steps: [RecipeStep] = [], language: String = "hu") {
        self.id = id
        self.source = source
        self.title = title
        self.summary = summary
        self.course = course
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.tags = tags
        self.imageURL = imageURL
        self.sourceURL = sourceURL
        self.ingredients = ingredients
        self.steps = steps
        self.language = language
    }

    public var totalMinutes: Int { prepMinutes + cookMinutes }
    public var needsTranslation: Bool { language != "hu" }
}

// MARK: - Beépített receptek betöltése

private struct BundledRecipeFile: Decodable {
    let version: Int
    let recipes: [BundledRecipe]
}

private struct BundledRecipe: Decodable {
    let id: String
    let title: String
    let summary: String
    let course: Course
    let servings: Int
    let prepMinutes: Int
    let cookMinutes: Int
    let tags: [String]
    let ingredients: [BundledIngredient]
    let steps: [RecipeStep]
}

private struct BundledIngredient: Decodable {
    let id: String
    let amount: Double?
    let unit: String
    let note: String?
    let optional: Bool?
}

public enum BundledRecipes {
    public static func load(catalog: IngredientCatalog) throws -> [Recipe] {
        guard let url = Bundle.module.url(forResource: "recipes_hu", withExtension: "json") else {
            throw FincsiError.resourceMissing("recipes_hu.json")
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(BundledRecipeFile.self, from: data)
        return file.recipes.map { item in
            let ingredients = item.ingredients.map { ing in
                RecipeIngredient(
                    ingredientID: ing.id,
                    name: catalog.name(of: ing.id),
                    amount: ing.amount,
                    unit: ing.unit,
                    note: ing.note,
                    optional: ing.optional ?? false
                )
            }
            return Recipe(
                id: item.id,
                source: .bundled,
                title: item.title,
                summary: item.summary,
                course: item.course,
                servings: item.servings,
                prepMinutes: item.prepMinutes,
                cookMinutes: item.cookMinutes,
                tags: item.tags,
                ingredients: ingredients,
                steps: item.steps,
                language: "hu"
            )
        }
    }
}
