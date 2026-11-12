import Foundation
@testable import FincsiKit

struct FakeHTTP: HTTPClient {
    var handler: @Sendable (URLRequest) throws -> (Data, Int)

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, status) = try handler(request)
        let url = request.url ?? URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

struct FakeTranslator: TextTranslator {
    var name = "Fake"
    var fail: FincsiError?

    func translate(_ texts: [String]) async throws -> [String] {
        if let fail = fail { throw fail }
        return texts.map { "HU:" + $0 }
    }
}

func makeEngine() throws -> (IngredientCatalog, MatchEngine, [Recipe]) {
    let catalog = try IngredientCatalog.loadBundled()
    let table = try SubstitutionTable.loadBundled()
    let recipes = try BundledRecipes.load(catalog: catalog)
    return (catalog, MatchEngine(catalog: catalog, substitutions: table), recipes)
}

func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("fincsi-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
