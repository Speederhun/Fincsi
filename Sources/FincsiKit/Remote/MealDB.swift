import Foundation

/// TheMealDB válasza: a `meals` lehet `null`.
struct MealDBResponse: Decodable {
    let meals: [[String: String?]]?
}

/// TheMealDB-ből érkező étel átalakítása az app saját receptmodelljére.
public struct MealDBMapper: Sendable {
    public let catalog: IngredientCatalog

    public init(catalog: IngredientCatalog) {
        self.catalog = catalog
    }

    public func recipe(from raw: [String: String]) -> Recipe? {
        guard let idMeal = raw["idMeal"], !idMeal.isEmpty,
              let title = raw["strMeal"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }

        var ingredients: [RecipeIngredient] = []
        for index in 1...20 {
            let name = (raw["strIngredient\(index)"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            let measureText = (raw["strMeasure\(index)"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let measure = MeasureParser.parse(measureText)
            let resolved = catalog.resolve(englishName: name)
            let displayName: String
            if let id = resolved {
                displayName = catalog.name(of: id)
            } else {
                displayName = name
            }
            var rawMeasure: String? = nil
            if measure.amount == nil && !measureText.isEmpty && measure.unit.isEmpty {
                rawMeasure = measureText
            }
            ingredients.append(RecipeIngredient(
                ingredientID: resolved,
                name: displayName,
                amount: measure.amount,
                unit: measure.unit,
                note: nil,
                optional: false,
                rawMeasure: rawMeasure
            ))
        }
        if ingredients.isEmpty { return nil }

        let instructions = raw["strInstructions"] ?? ""
        let steps = InstructionParser.steps(from: instructions)
        if steps.isEmpty { return nil }

        let category = (raw["strCategory"] ?? "").trimmingCharacters(in: .whitespaces)
        let area = (raw["strArea"] ?? "").trimmingCharacters(in: .whitespaces)
        var tags: [String] = []
        if !area.isEmpty { tags.append(area) }
        if !category.isEmpty { tags.append(category) }
        if let rawTags = raw["strTags"] {
            for tag in rawTags.split(separator: ",") {
                let cleaned = tag.trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty && !tags.contains(cleaned) { tags.append(cleaned) }
            }
        }

        return Recipe(
            id: "mealdb-\(idMeal)",
            source: .mealdb,
            title: title,
            summary: "",
            course: Self.course(category: category, title: title),
            servings: 4,
            prepMinutes: 0,
            cookMinutes: 0,
            tags: tags,
            imageURL: Self.url(raw["strMealThumb"]),
            sourceURL: Self.url(raw["strSource"]),
            ingredients: ingredients,
            steps: steps,
            language: "en"
        )
    }

    static func course(category: String, title: String) -> Course {
        let lowerTitle = title.lowercased()
        if lowerTitle.contains("soup") || lowerTitle.contains("stew") && category.lowercased() == "starter" {
            return .leves
        }
        switch category.lowercased() {
        case "dessert": return .desszert
        case "breakfast": return .reggeli
        case "side": return .koret
        case "pasta": return .tesztaetel
        case "starter": return .egyeb
        case "": return .egyeb
        default: return .foetel
        }
    }

    static func url(_ text: String?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }
}

public struct MealDBClient: Sendable {
    public static let defaultKey = "1"
    public static let letters: [Character] = Array("abcdefghijklmnopqrstuvwxyz")

    private let http: HTTPClient
    private let apiKey: String

    public init(http: HTTPClient, apiKey: String = MealDBClient.defaultKey) {
        self.http = http
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = trimmed.isEmpty ? MealDBClient.defaultKey : trimmed
    }

    func endpoint(path: String, query: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.themealdb.com"
        components.path = "/api/json/v1/\(apiKey)/\(path)"
        components.queryItems = query
        return components.url
    }

    /// Egy betűvel kezdődő ételek letöltése.
    public func meals(startingWith letter: Character) async throws -> [[String: String]] {
        guard let url = endpoint(path: "search.php", query: [URLQueryItem(name: "f", value: String(letter))]) else {
            throw FincsiError.badResponse
        }
        let (data, response) = try await Retry.perform { try await http.get(url) }
        guard (200...299).contains(response.statusCode) else {
            throw response.statusCode == 429 ? FincsiError.rateLimited : FincsiError.badResponse
        }
        return try Self.decodeMeals(data)
    }

    static func decodeMeals(_ data: Data) throws -> [[String: String]] {
        let decoded: MealDBResponse
        do {
            decoded = try JSONDecoder().decode(MealDBResponse.self, from: data)
        } catch {
            throw FincsiError.badResponse
        }
        guard let meals = decoded.meals else { return [] }
        return meals.map { dictionary in
            var flat: [String: String] = [:]
            for (key, value) in dictionary {
                if let value = value {
                    flat[key] = value
                }
            }
            return flat
        }
    }

    public struct FetchResult: Sendable {
        public let meals: [[String: String]]
        public let failedLetters: [Character]
        public let lastError: FincsiError?
    }

    /// Az összes (a-z) betű letöltése, korlátozott párhuzamossággal. Részleges siker esetén is visszaadja, ami megvan.
    public func fetchAll(maxConcurrent: Int = 4) async -> FetchResult {
        var collected: [[String: String]] = []
        var failed: [Character] = []
        var lastError: FincsiError? = nil

        typealias Outcome = Result<[[String: String]], Error>
        let letters = Self.letters
        let batchSize = max(1, maxConcurrent)
        var start = 0
        while start < letters.count {
            let batch = Array(letters[start..<min(start + batchSize, letters.count)])
            start += batchSize
            var outcomes: [(Character, Outcome)] = []
            await withTaskGroup(of: (Character, Outcome).self) { group in
                for letter in batch {
                    group.addTask {
                        do {
                            let meals = try await self.meals(startingWith: letter)
                            return (letter, Outcome.success(meals))
                        } catch {
                            return (letter, Outcome.failure(error))
                        }
                    }
                }
                for await outcome in group {
                    outcomes.append(outcome)
                }
            }
            for (letter, outcome) in outcomes {
                switch outcome {
                case .success(let meals):
                    collected.append(contentsOf: meals)
                case .failure(let error):
                    failed.append(letter)
                    lastError = (error as? FincsiError) ?? FincsiError.network(error.localizedDescription)
                }
            }
        }
        return FetchResult(meals: collected, failedLetters: failed, lastError: lastError)
    }
}
