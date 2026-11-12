import Foundation

/// Az alapanyagok tulajdonságai, amelyek alapján az étrendek szűrnek.
public enum IngredientTag: String, Codable, Hashable, Sendable {
    case gluten
    case meat
    case fish
    case dairy
    case lactose
    case egg
    case honey
    case nut
    case animal
}

/// A támogatott étrendek. A szűrés kizárólag az alapanyag-címkékre épül, ezért megbízható és előre kiszámítható.
public enum Diet: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case glutenFree
    case vegan
    case vegetarian
    case lactoseFree
    case nutFree

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .glutenFree: return "Gluténmentes"
        case .vegan: return "Vegán"
        case .vegetarian: return "Vegetáriánus"
        case .lactoseFree: return "Laktózmentes"
        case .nutFree: return "Dió- és mogyorómentes"
        }
    }

    public var detail: String {
        switch self {
        case .glutenFree: return "Búza, rozs, árpa és zab nélkül, a recept cseréket javasol."
        case .vegan: return "Hús, hal, tojás, tejtermék és méz nélkül."
        case .vegetarian: return "Hús és hal nélkül."
        case .lactoseFree: return "Tej és tejtermékek helyett laktózmentes vagy növényi alternatívával."
        case .nutFree: return "Dió, mogyoró, mandula és társaik nélkül."
        }
    }

    /// Azok a címkék, amelyeket az étrend nem enged meg.
    public var forbiddenTags: Set<IngredientTag> {
        switch self {
        case .glutenFree: return [.gluten]
        case .vegan: return [.meat, .fish, .dairy, .egg, .honey, .animal]
        case .vegetarian: return [.meat, .fish, .animal]
        case .lactoseFree: return [.lactose]
        case .nutFree: return [.nut]
        }
    }

    /// Több étrend együttes tiltólistája.
    public static func forbiddenTags(for diets: Set<Diet>) -> Set<IngredientTag> {
        var result = Set<IngredientTag>()
        for diet in diets {
            result.formUnion(diet.forbiddenTags)
        }
        return result
    }

    /// Állandó sorrend a felületen és a kimenetben.
    public static func sorted(_ diets: Set<Diet>) -> [Diet] {
        return Diet.allCases.filter { diets.contains($0) }
    }
}
