import XCTest
@testable import FincsiKit

final class PersistenceTests: XCTestCase {
    func testUserDataRoundTrip() throws {
        var data = UserData()
        data.setInPantry("hagyma", true)
        data.toggleFavorite("r1")
        data.diets = [.vegan]
        let store = JSONFileStore<UserData>(url: tempDirectory().appendingPathComponent("u.json"))
        try store.save(data)
        XCTAssertEqual(store.load(), data)
    }

    func testCorruptFileIsQuarantined() throws {
        let url = tempDirectory().appendingPathComponent("u.json")
        try Data("{ nem json".utf8).write(to: url)
        let store = JSONFileStore<UserData>(url: url)
        XCTAssertNil(store.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
        XCTAssertNil(store.load())
    }

    func testDecodingOldOrPartialFile() throws {
        let json = Data("{\"pantry\":[\"so\"],\"diets\":[\"vegan\",\"jövőbeli\"]}".utf8)
        let data = try JSONDecoder().decode(UserData.self, from: json)
        XCTAssertEqual(data.pantry, ["so"])
        XCTAssertEqual(data.diets, [.vegan])
        XCTAssertTrue(data.settings.assumeStaples)
    }

    func testPantryAndExclusionAreMutuallyExclusive() {
        var data = UserData()
        data.setInPantry("tej", true)
        data.setExcluded("tej", true)
        XCTAssertFalse(data.pantry.contains("tej"))
        data.setInPantry("tej", true)
        XCTAssertFalse(data.excluded.contains("tej"))
    }

    func testShoppingMergesAndMovesToPantry() {
        var data = UserData()
        data.addToShopping(ingredientID: "liszt", name: "Liszt", amount: 200, unit: "g", recipeTitle: "A")
        data.addToShopping(ingredientID: "liszt", name: "Liszt", amount: 300, unit: "g", recipeTitle: "B")
        data.addToShopping(ingredientID: "liszt", name: "Liszt", amount: 1, unit: "kg", recipeTitle: nil)
        XCTAssertEqual(data.shopping.count, 2)
        XCTAssertEqual(data.shopping[0].amount, 500)
        XCTAssertEqual(data.shopping[0].recipeTitles, ["A", "B"])
        data.shopping[0].checked = true
        XCTAssertEqual(data.moveCheckedToPantry(), 1)
        XCTAssertTrue(data.pantry.contains("liszt"))
        XCTAssertEqual(data.shopping.count, 1)
    }

    func testHistoryDedupesAndLimits() {
        var data = UserData()
        for index in 0..<120 { data.markCooked(recipeID: "r\(index)", title: "R") }
        data.markCooked(recipeID: "r5", title: "R")
        XCTAssertEqual(data.history.count, 100)
        XCTAssertEqual(data.history.first?.recipeID, "r5")
        XCTAssertEqual(data.history.filter { $0.recipeID == "r5" }.count, 1)
    }

    func testRecipeStoreSyncKeepsOldOnPartialFailure() async throws {
        let catalog = try IngredientCatalog.loadBundled()
        let body = Data("{\"meals\":[{\"idMeal\":\"1\",\"strMeal\":\"A\",\"strInstructions\":\"Boil it.\",\"strIngredient1\":\"Onion\",\"strMeasure1\":\"1\"}]}".utf8)
        let http = FakeHTTP { _ in (body, 200) }
        let dir = tempDirectory()
        let store = RecipeStore(directory: dir)
        let report = try await store.sync(client: MealDBClient(http: http), mapper: MealDBMapper(catalog: catalog))
        XCTAssertEqual(report.total, 1)
        XCTAssertEqual(report.failedLetters, 0)

        let failing = FakeHTTP { _ in (Data(), 500) }
        do {
            _ = try await store.sync(client: MealDBClient(http: failing), mapper: MealDBMapper(catalog: catalog))
            XCTFail("hibát vártunk")
        } catch {}
        let count = await store.remoteRecipes.count
        XCTAssertEqual(count, 1)

        let reopened = RecipeStore(directory: dir)
        let reopenedCount = await reopened.remoteRecipes.count
        XCTAssertEqual(reopenedCount, 1)
    }
}
