import Foundation

/// A felhasználó beállításai, amelyek alapján a receptek párosítása történik.
public struct UserProfile: Equatable, Sendable {
    public var pantry: Set<String>
    public var excluded: Set<String>
    public var diets: Set<Diet>
    /// Só, bors, víz, étolaj mindig van otthon.
    public var assumeStaples: Bool
    /// Azonosítatlan alapanyagot tartalmazó receptek mutatása étrendi szűrés mellett is.
    public var allowUncertain: Bool

    public init(pantry: Set<String> = [], excluded: Set<String> = [], diets: Set<Diet> = [],
                assumeStaples: Bool = true, allowUncertain: Bool = false) {
        self.pantry = pantry
        self.excluded = excluded
        self.diets = diets
        self.assumeStaples = assumeStaples
        self.allowUncertain = allowUncertain
    }
}

public enum Availability: String, Sendable, Hashable {
    /// Van otthon.
    case have
    /// Alapvető alapanyag, feltételezzük, hogy van.
    case staple
    /// Meg kell venni.
    case missing
    /// A recept ezen részét elhagyjuk (elhagyható hozzávaló, ami nem fér az étrendbe).
    case omitted
    /// Nem azonosított alapanyag.
    case unresolved
    /// Nem fér az étrendbe, és nincs helyettesítője, vagy ki van zárva.
    case blocked
}

public struct IngredientEvaluation: Identifiable, Hashable, Sendable {
    public let index: Int
    public let ingredient: RecipeIngredient
    /// A ténylegesen használandó alapanyag azonosítója (csere esetén a helyettesítőé).
    public let effectiveID: String?
    public let effectiveName: String
    public let substitution: Substitution?
    public let availability: Availability

    public var id: Int { index }
    public var isSubstituted: Bool { substitution != nil }
}

public enum Verdict: String, Sendable, Hashable {
    /// Változtatás nélkül megfelel.
    case compatible
    /// Cserékkel vagy elhagyásokkal megfelel.
    case adapted
    /// Kizárt alapanyagot tartalmaz („nem kérem”).
    case excluded
    /// Étrendbe nem fér, és nincs helyettesítő.
    case dietConflict
    /// Azonosítatlan alapanyag miatt nem ellenőrizhető az étrendi megfelelés.
    case uncertain

    public var isUsable: Bool {
        return self == .compatible || self == .adapted
    }
}

public struct RecipeMatch: Identifiable, Hashable, Sendable {
    public let recipe: Recipe
    public let verdict: Verdict
    public let evaluations: [IngredientEvaluation]
    public let blockers: [String]
    public let missingCount: Int
    public let haveCount: Int
    public let requiredCount: Int
    public let substitutionCount: Int
    public let omittedCount: Int
    public let unresolvedCount: Int

    public var id: String { recipe.id }

    /// A nem alapvető, szükséges hozzávalók mekkora része van meg (0...1).
    public var coverage: Double {
        let relevant = evaluations.filter { eval in
            guard !eval.ingredient.optional else { return false }
            switch eval.availability {
            case .have, .missing, .unresolved: return true
            default: return false
            }
        }
        if relevant.isEmpty { return 1 }
        let have = relevant.filter { $0.availability == .have }.count
        return Double(have) / Double(relevant.count)
    }

    public var substitutions: [IngredientEvaluation] {
        return evaluations.filter { $0.substitution != nil }
    }

    public var omitted: [IngredientEvaluation] {
        return evaluations.filter { $0.availability == .omitted }
    }

    public var missing: [IngredientEvaluation] {
        return evaluations.filter { $0.availability == .missing || ($0.availability == .unresolved && !$0.ingredient.optional) }
    }

    public var isCookableNow: Bool {
        return verdict.isUsable && missingCount == 0
    }
}

/// A recept-párosító: ellenőrzi az étrendet, a „nem kérem” listát, helyettesít, és megszámolja a hiányzó hozzávalókat.
public struct MatchEngine: Sendable {
    public let catalog: IngredientCatalog
    public let substitutions: SubstitutionTable

    public init(catalog: IngredientCatalog, substitutions: SubstitutionTable) {
        self.catalog = catalog
        self.substitutions = substitutions
    }

    // MARK: - Kontextus

    private struct Context {
        let profile: UserProfile
        let pantryClosure: Set<String>
        let forbidden: Set<IngredientTag>
        let restricted: Bool
    }

    private func makeContext(_ profile: UserProfile) -> Context {
        var closure = Set<String>()
        for item in profile.pantry {
            closure.insert(item)
            if let family = catalog[item]?.family {
                closure.insert(family)
            }
        }
        let restricted = !profile.diets.isEmpty || !profile.excluded.isEmpty
        return Context(profile: profile, pantryClosure: closure,
                       forbidden: Diet.forbiddenTags(for: profile.diets), restricted: restricted)
    }

    // MARK: - Kiértékelés

    public func evaluate(_ recipe: Recipe, profile: UserProfile) -> RecipeMatch {
        return evaluate(recipe, context: makeContext(profile))
    }

    public func evaluateAll(_ recipes: [Recipe], profile: UserProfile) -> [RecipeMatch] {
        let context = makeContext(profile)
        return recipes.map { evaluate($0, context: context) }
    }

    private func availability(of id: String, context: Context) -> Availability {
        if context.pantryClosure.contains(id) { return .have }
        if context.profile.assumeStaples, catalog[id]?.staple == true { return .staple }
        return .missing
    }

    /// A felhasználó étrendjéhez illő helyettesítő: a kamrában lévőt részesíti előnyben.
    private func chooseSubstitution(for id: String, violatedDiets: [Diet], context: Context) -> Substitution? {
        var candidates: [Substitution] = []
        var seen = Set<String>()
        for diet in violatedDiets {
            for sub in substitutions.candidates(for: id, diet: diet) where !seen.contains(sub.to) {
                seen.insert(sub.to)
                candidates.append(sub)
            }
        }
        let valid = candidates.filter { sub in
            guard let target = catalog[sub.to] else { return false }
            if !target.tags.isDisjoint(with: context.forbidden) { return false }
            if catalog.isExcluded(sub.to, by: context.profile.excluded) { return false }
            return true
        }
        if let owned = valid.first(where: { context.pantryClosure.contains($0.to) }) {
            return owned
        }
        return valid.first
    }

    private func evaluate(_ recipe: Recipe, context: Context) -> RecipeMatch {
        var evaluations: [IngredientEvaluation] = []
        var blockers: [String] = []
        var excludedHit = false
        var uncertain = 0

        for (index, ingredient) in recipe.ingredients.enumerated() {
            guard let id = ingredient.ingredientID, let known = catalog[id] else {
                // Azonosítatlan alapanyag.
                if context.restricted && !ingredient.optional {
                    uncertain += 1
                }
                evaluations.append(IngredientEvaluation(index: index, ingredient: ingredient, effectiveID: nil,
                                                        effectiveName: ingredient.name, substitution: nil,
                                                        availability: .unresolved))
                continue
            }

            // 1. „Nem kérem” lista
            if catalog.isExcluded(id, by: context.profile.excluded) {
                if ingredient.optional {
                    evaluations.append(IngredientEvaluation(index: index, ingredient: ingredient, effectiveID: nil,
                                                            effectiveName: known.name, substitution: nil,
                                                            availability: .omitted))
                } else {
                    excludedHit = true
                    blockers.append(known.name)
                    evaluations.append(IngredientEvaluation(index: index, ingredient: ingredient, effectiveID: id,
                                                            effectiveName: known.name, substitution: nil,
                                                            availability: .blocked))
                }
                continue
            }

            // 2. Étrend
            let violated = Diet.sorted(context.profile.diets).filter { !known.tags.isDisjoint(with: $0.forbiddenTags) }
            if violated.isEmpty {
                evaluations.append(IngredientEvaluation(index: index, ingredient: ingredient, effectiveID: id,
                                                        effectiveName: known.name, substitution: nil,
                                                        availability: availability(of: id, context: context)))
                continue
            }

            if let sub = chooseSubstitution(for: id, violatedDiets: violated, context: context) {
                let targetName = catalog.name(of: sub.to)
                evaluations.append(IngredientEvaluation(index: index, ingredient: ingredient, effectiveID: sub.to,
                                                        effectiveName: targetName, substitution: sub,
                                                        availability: availability(of: sub.to, context: context)))
            } else if ingredient.optional {
                evaluations.append(IngredientEvaluation(index: index, ingredient: ingredient, effectiveID: nil,
                                                        effectiveName: known.name, substitution: nil,
                                                        availability: .omitted))
            } else {
                blockers.append(known.name)
                evaluations.append(IngredientEvaluation(index: index, ingredient: ingredient, effectiveID: id,
                                                        effectiveName: known.name, substitution: nil,
                                                        availability: .blocked))
            }
        }

        let verdict: Verdict
        let substitutionCount = evaluations.filter { $0.substitution != nil }.count
        let omittedCount = evaluations.filter { $0.availability == .omitted }.count
        if excludedHit {
            verdict = .excluded
        } else if !blockers.isEmpty {
            verdict = .dietConflict
        } else if uncertain > 0 && !context.profile.allowUncertain {
            verdict = .uncertain
        } else if substitutionCount > 0 || omittedCount > 0 {
            verdict = .adapted
        } else {
            verdict = .compatible
        }

        let required = evaluations.filter { eval in
            if eval.ingredient.optional { return false }
            return eval.availability != .omitted
        }
        let missingCount = required.filter { $0.availability == .missing || $0.availability == .unresolved }.count
        let haveCount = required.filter { $0.availability == .have || $0.availability == .staple }.count
        let unresolvedCount = evaluations.filter { $0.availability == .unresolved }.count

        return RecipeMatch(recipe: recipe, verdict: verdict, evaluations: evaluations, blockers: blockers,
                           missingCount: missingCount, haveCount: haveCount, requiredCount: required.count,
                           substitutionCount: substitutionCount, omittedCount: omittedCount,
                           unresolvedCount: unresolvedCount)
    }

    // MARK: - Rendezés

    /// Kevesebb hiányzó hozzávaló, kevesebb csere, rövidebb elkészítési idő, majd név szerint.
    public func ranked(_ matches: [RecipeMatch]) -> [RecipeMatch] {
        let locale = Locale(identifier: "hu_HU")
        return matches.sorted { lhs, rhs in
            if lhs.missingCount != rhs.missingCount { return lhs.missingCount < rhs.missingCount }
            if lhs.substitutionCount != rhs.substitutionCount { return lhs.substitutionCount < rhs.substitutionCount }
            if lhs.coverage != rhs.coverage { return lhs.coverage > rhs.coverage }
            if lhs.recipe.totalMinutes != rhs.recipe.totalMinutes { return lhs.recipe.totalMinutes < rhs.recipe.totalMinutes }
            return lhs.recipe.title.compare(rhs.recipe.title, locale: locale) == .orderedAscending
        }
    }

    // MARK: - Természetes megfelelés

    /// Azok az étrendek, amelyeknek a recept eleve, csere nélkül megfelel (jelvényekhez).
    /// Ha egy hozzávaló nem azonosítható, az étrendi megfelelést nem állítjuk.
    public func naturalDiets(of recipe: Recipe) -> Set<Diet> {
        var result = Set<Diet>()
        for diet in Diet.allCases {
            var ok = true
            for ingredient in recipe.ingredients {
                guard let id = ingredient.ingredientID, let known = catalog[id] else {
                    ok = false
                    break
                }
                if !known.tags.isDisjoint(with: diet.forbiddenTags) {
                    ok = false
                    break
                }
            }
            if ok { result.insert(diet) }
        }
        return result
    }
}
