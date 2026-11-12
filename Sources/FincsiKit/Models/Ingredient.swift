import Foundation

public struct IngredientCategory: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let order: Int

    public init(id: String, name: String, order: Int) {
        self.id = id
        self.name = name
        self.order = order
    }
}

public struct Ingredient: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: String
    public let tags: Set<IngredientTag>
    public let aliasesEN: [String]
    public let aliasesHU: [String]
    /// Ha ki van töltve, az alapanyag egy általánosabb alapanyag-család tagja (pl. a csiperkegomba a „gomba” családé).
    public let family: String?
    /// Alapvető alapanyag (só, bors, víz, étolaj), amiből feltételezzük, hogy mindig van otthon.
    public let staple: Bool

    public init(id: String, name: String, category: String, tags: Set<IngredientTag> = [],
                aliasesEN: [String] = [], aliasesHU: [String] = [], family: String? = nil, staple: Bool = false) {
        self.id = id
        self.name = name
        self.category = category
        self.tags = tags
        self.aliasesEN = aliasesEN
        self.aliasesHU = aliasesHU
        self.family = family
        self.staple = staple
    }
}
