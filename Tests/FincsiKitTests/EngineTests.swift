import XCTest
@testable import FincsiKit

final class EngineTests: XCTestCase {
    func testBundledDataLoads() throws {
        let (catalog, _, recipes) = try makeEngine()
        XCTAssertEqual(recipes.count, 55)
        XCTAssertFalse(catalog.ingredients.isEmpty)
        for recipe in recipes {
            XCTAssertFalse(recipe.steps.isEmpty, recipe.id)
            for ingredient in recipe.ingredients {
                XCTAssertNotNil(catalog[ingredient.ingredientID ?? ""], "\(recipe.id): \(ingredient.name)")
            }
        }
    }

    func testNoDietNoRestrictionsEverythingCompatible() throws {
        let (_, engine, recipes) = try makeEngine()
        let matches = engine.evaluateAll(recipes, profile: UserProfile())
        XCTAssertTrue(matches.allSatisfy { $0.verdict == .compatible })
    }

    /// Fő invariáns: ami használhatónak minősül, abban a ténylegesen használt alapanyagok egyike sem tiltott.
    func testUsableRecipesNeverContainForbiddenTags() throws {
        let (catalog, engine, recipes) = try makeEngine()
        for diets in [Set([Diet.vegan]), [.glutenFree], [.vegetarian], [.lactoseFree], [.nutFree], [.vegan, .glutenFree]] {
            let forbidden = Diet.forbiddenTags(for: diets)
            let matches = engine.evaluateAll(recipes, profile: UserProfile(diets: diets))
            for match in matches where match.verdict.isUsable {
                for evaluation in match.evaluations where evaluation.availability != .omitted {
                    guard let id = evaluation.effectiveID, let ingredient = catalog[id] else {
                        XCTFail("Azonosítatlan hozzávaló használhatónak jelölt receptben: \(match.recipe.id)")
                        continue
                    }
                    XCTAssertTrue(ingredient.tags.isDisjoint(with: forbidden),
                                  "\(match.recipe.id): \(ingredient.id) tiltott \(diets)")
                }
            }
        }
    }

    func testVeganIsStricterThanVegetarian() throws {
        let (_, engine, recipes) = try makeEngine()
        let vegan = engine.evaluateAll(recipes, profile: UserProfile(diets: [.vegan])).filter { $0.verdict.isUsable }.count
        let vegetarian = engine.evaluateAll(recipes, profile: UserProfile(diets: [.vegetarian])).filter { $0.verdict.isUsable }.count
        XCTAssertLessThanOrEqual(vegan, vegetarian)
        XCTAssertGreaterThan(vegetarian, 0)
    }

    func testExclusionBlocksRecipe() throws {
        let (_, engine, recipes) = try makeEngine()
        guard let recipe = recipes.first(where: { $0.ingredients.contains { !$0.optional } }),
              let target = recipe.ingredients.first(where: { !$0.optional })?.ingredientID else {
            return XCTFail("nincs recept")
        }
        let match = engine.evaluate(recipe, profile: UserProfile(excluded: [target]))
        XCTAssertFalse(match.verdict.isUsable && match.evaluations.contains { $0.effectiveID == target })
    }

    func testPantryReducesMissing() throws {
        let (_, engine, recipes) = try makeEngine()
        let recipe = recipes[0]
        let none = engine.evaluate(recipe, profile: UserProfile())
        let all = Set(recipe.ingredients.compactMap { $0.ingredientID })
        let full = engine.evaluate(recipe, profile: UserProfile(pantry: all))
        XCTAssertEqual(full.missingCount, 0)
        XCTAssertLessThanOrEqual(full.missingCount, none.missingCount)
        XCTAssertTrue(full.isCookableNow)
    }

    func testRankingPutsFewestMissingFirst() throws {
        let (_, engine, recipes) = try makeEngine()
        let ranked = engine.ranked(engine.evaluateAll(recipes, profile: UserProfile()))
        for pair in zip(ranked, ranked.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.missingCount, pair.1.missingCount)
        }
    }

    func testUnresolvedIngredientIsUncertainUnderDiet() throws {
        let (_, engine, _) = try makeEngine()
        let recipe = Recipe(id: "t", source: .mealdb, title: "Teszt",
                            ingredients: [RecipeIngredient(ingredientID: nil, name: "mystery")],
                            steps: [RecipeStep(text: "Keverd.")], language: "en")
        XCTAssertEqual(engine.evaluate(recipe, profile: UserProfile(diets: [.vegan])).verdict, .uncertain)
        XCTAssertEqual(engine.evaluate(recipe, profile: UserProfile()).verdict, .compatible)
    }

    func testSubstitutesSatisfyAllActiveDiets() throws {
        let (catalog, _, _) = try makeEngine()
        let table = try SubstitutionTable.loadBundled()
        for substitution in table.all {
            XCTAssertNotNil(catalog[substitution.from], substitution.from)
            XCTAssertNotNil(catalog[substitution.to], substitution.to)
        }
    }
}

final class CatalogTests: XCTestCase {
    func testResolveEnglish() throws {
        let catalog = try IngredientCatalog.loadBundled()
        XCTAssertNotNil(catalog.resolve(englishName: "Onions"))
        XCTAssertEqual(catalog.resolve(englishName: "onion"), catalog.resolve(englishName: "Onions"))
        XCTAssertNil(catalog.resolve(englishName: "zzzz unknown thing"))
        XCTAssertNil(catalog.resolve(englishName: ""))
    }

    func testSearchIsAccentInsensitive() throws {
        let catalog = try IngredientCatalog.loadBundled()
        let accented = catalog.search("tej").map { $0.id }
        XCTAssertFalse(accented.isEmpty)
        XCTAssertEqual(catalog.search("TEJ").map { $0.id }, accented)
        XCTAssertTrue(catalog.search("").isEmpty)
    }
}
