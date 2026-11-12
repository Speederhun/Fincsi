import Foundation

/// Egy helyettesítési javaslat: az `ingredient` helyett a `to` alapanyag használható az adott étrendben.
public struct Substitution: Codable, Hashable, Sendable {
    public let ingredient: String
    public let diet: Diet
    public let to: String
    public let note: String

    public init(ingredient: String, diet: Diet, to: String, note: String) {
        self.ingredient = ingredient
        self.diet = diet
        self.to = to
        self.note = note
    }
}

private struct SubstitutionFile: Decodable {
    let version: Int
    let substitutions: [Substitution]
}

public struct SubstitutionTable: Sendable {
    private let table: [String: [Substitution]]
    public let all: [Substitution]

    public init(_ substitutions: [Substitution]) {
        self.all = substitutions
        var map: [String: [Substitution]] = [:]
        for sub in substitutions {
            map["\(sub.ingredient)|\(sub.diet.rawValue)", default: []].append(sub)
        }
        self.table = map
    }

    public static func loadBundled() throws -> SubstitutionTable {
        guard let url = Bundle.module.url(forResource: "substitutions", withExtension: "json") else {
            throw FincsiError.resourceMissing("substitutions.json")
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(SubstitutionFile.self, from: data)
        return SubstitutionTable(file.substitutions)
    }

    /// Az adott alapanyag helyettesítői az adott étrendhez, a megadott sorrendben.
    public func candidates(for ingredient: String, diet: Diet) -> [Substitution] {
        return table["\(ingredient)|\(diet.rawValue)"] ?? []
    }
}
