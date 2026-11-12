import XCTest
@testable import FincsiKit

final class RemoteTests: XCTestCase {
    private func meal(_ id: String) -> [String: String] {
        ["idMeal": id, "strMeal": "Chicken Soup", "strCategory": "Chicken", "strArea": "Hungarian",
         "strInstructions": "Chop the onion.\r\nBoil for 20 minutes.",
         "strIngredient1": "Onion", "strMeasure1": "1",
         "strIngredient2": "Chicken", "strMeasure2": "200g"]
    }

    func testMapperBuildsRecipe() throws {
        let catalog = try IngredientCatalog.loadBundled()
        let recipe = MealDBMapper(catalog: catalog).recipe(from: meal("1"))
        XCTAssertEqual(recipe?.id, "mealdb-1")
        XCTAssertEqual(recipe?.language, "en")
        XCTAssertFalse(recipe?.steps.isEmpty ?? true)
        XCTAssertNil(MealDBMapper(catalog: catalog).recipe(from: ["idMeal": "2"]))
    }

    func testDecodeNullMeals() throws {
        let data = Data("{\"meals\":null}".utf8)
        XCTAssertTrue(try MealDBClient.decodeMeals(data).isEmpty)
        XCTAssertThrowsError(try MealDBClient.decodeMeals(Data("nope".utf8)))
    }

    func testFetchAllPartialFailure() async {
        let body = Data("{\"meals\":[{\"idMeal\":\"1\",\"strMeal\":\"A\"}]}".utf8)
        let http = FakeHTTP { request in
            let query = request.url?.query ?? ""
            return query.contains("f=b") ? (Data(), 404) : (body, 200)
        }
        let result = await MealDBClient(http: http).fetchAll()
        XCTAssertEqual(result.failedLetters, ["b"])
        XCTAssertEqual(result.meals.count, 25)
    }
}

final class TranslationTests: XCTestCase {
    func testChunkerRespectsLimit() {
        let text = String(repeating: "Hello world. ", count: 100)
        let chunks = TextChunker.split(text, maxLength: 450)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 450 })
        XCTAssertTrue(TextChunker.split("   ", maxLength: 450).isEmpty)
        let long = String(repeating: "a", count: 1000)
        XCTAssertTrue(TextChunker.split(long, maxLength: 450).allSatisfy { $0.count <= 450 })
    }

    func testRecipeTranslationAppliesAndKeepsTimers() async throws {
        let recipe = Recipe(id: "r", source: .mealdb, title: "Soup",
                            ingredients: [RecipeIngredient(ingredientID: nil, name: "mystery")],
                            steps: [RecipeStep(text: "Boil.", timerMinutes: 10)], language: "en")
        let translated = try await RecipeTranslator(translators: [FakeTranslator()]).translate(recipe)
        let result = recipe.applying(translated)
        XCTAssertEqual(result.title, "HU:Soup")
        XCTAssertEqual(result.steps[0].text, "HU:Boil.")
        XCTAssertEqual(result.steps[0].timerMinutes, 10)
        XCTAssertEqual(result.ingredients[0].name, "HU:mystery")
        XCTAssertEqual(result.language, "hu")
    }

    func testFallbackToSecondTranslator() async throws {
        let recipe = Recipe(id: "r", source: .mealdb, title: "Soup", steps: [RecipeStep(text: "Boil.")], language: "en")
        let chain = RecipeTranslator(translators: [FakeTranslator(name: "A", fail: .quotaExceeded), FakeTranslator(name: "B")])
        let translated = try await chain.translate(recipe)
        XCTAssertEqual(translated.translator, "B")
    }

    func testAllFailThrowsLastError() async {
        let recipe = Recipe(id: "r", source: .mealdb, title: "Soup", steps: [RecipeStep(text: "Boil.")], language: "en")
        let chain = RecipeTranslator(translators: [FakeTranslator(fail: .quotaExceeded)])
        do {
            _ = try await chain.translate(recipe)
            XCTFail("hibát vártunk")
        } catch {
            XCTAssertEqual(error as? FincsiError, .quotaExceeded)
        }
    }

    func testDeepLParsesResponse() async throws {
        let http = FakeHTTP { _ in (Data("{\"translations\":[{\"text\":\"Leves\"}]}".utf8), 200) }
        let result = try await DeepLTranslator(http: http, apiKey: "k:fx").translate(["Soup"])
        XCTAssertEqual(result, ["Leves"])
    }

    func testDeepLQuota() async {
        let http = FakeHTTP { _ in (Data(), 456) }
        do {
            _ = try await DeepLTranslator(http: http, apiKey: "k").translate(["Soup"])
            XCTFail()
        } catch {
            XCTAssertEqual(error as? FincsiError, .quotaExceeded)
        }
    }

    func testMyMemoryParsesAndDetectsQuota() async throws {
        let ok = FakeHTTP { _ in (Data("{\"responseData\":{\"translatedText\":\"Leves &amp; k&#39;\"},\"responseStatus\":200}".utf8), 200) }
        let result = try await MyMemoryTranslator(http: ok).translate(["Soup"])
        XCTAssertEqual(result, ["Leves & k'"])

        let quota = FakeHTTP { _ in (Data("{\"responseData\":{\"translatedText\":\"MYMEMORY WARNING: x\"},\"quotaFinished\":true,\"responseStatus\":\"429\"}".utf8), 200) }
        do {
            _ = try await MyMemoryTranslator(http: quota).translate(["Soup"])
            XCTFail()
        } catch {
            XCTAssertEqual(error as? FincsiError, .quotaExceeded)
        }
    }
}
