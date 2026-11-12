import SwiftUI
import FincsiKit

struct RecipeDetailView: View {
    let recipeID: String
    @Environment(AppModel.self) private var model
    @State private var servings: Int = 0
    @State private var cooking = false
    @State private var addedToList = false

    var body: some View {
        if let match = model.match(id: recipeID) {
            detail(match)
        } else {
            ContentUnavailableView("A recept nem érhető el", systemImage: "questionmark.folder",
                                   description: Text("Lehet, hogy törölted a letöltött recepteket."))
        }
    }

    private func detail(_ match: RecipeMatch) -> some View {
        let recipe = match.recipe
        let shown = servings > 0 ? servings : recipe.servings
        let scale = Double(shown) / Double(max(1, recipe.servings))
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(recipe)
                summaryBadges(match)
                if !match.substitutions.isEmpty || match.omittedCount > 0 {
                    adaptationNote(match)
                }
                if recipe.needsTranslation {
                    translationBox(recipe)
                }
                ingredientsSection(match, scale: scale, servings: shown, baseServings: recipe.servings)
                stepsSection(recipe)
                footer(recipe)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: shareText(match, scale: scale)) {
                    Label("Megosztás", systemImage: "square.and.arrow.up")
                }
                Button {
                    model.update { $0.toggleFavorite(recipe.id) }
                } label: {
                    Image(systemName: model.data.isFavorite(recipe.id) ? "heart.fill" : "heart")
                }
                .accessibilityLabel(model.data.isFavorite(recipe.id) ? "Törlés a kedvencek közül" : "Kedvenc")
            }
        }
        .fullScreenCover(isPresented: $cooking) {
            CookingView(recipe: recipe) {
                model.markCooked(recipe)
            }
        }
        .task(id: recipe.id) {
            if servings == 0 { servings = recipe.servings }
            if recipe.needsTranslation && model.data.settings.autoTranslate {
                await model.translate(recipe.id)
            }
        }
    }

    // MARK: Részek

    private func header(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = recipe.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Rectangle().fill(Theme.paprika.opacity(0.12))
                    }
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            }
            Text(recipe.title).font(.title2.bold())
            if !recipe.summary.isEmpty {
                Text(recipe.summary).foregroundStyle(.secondary)
            }
        }
    }

    private func summaryBadges(_ match: RecipeMatch) -> some View {
        let recipe = match.recipe
        let natural = model.core?.engine.naturalDiets(of: recipe) ?? []
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Badge(text: recipe.course.title, symbol: recipe.course.symbol, tint: Theme.paprika)
                if recipe.totalMinutes > 0 {
                    Badge(text: minutesText(recipe.totalMinutes), symbol: "clock")
                }
                ForEach(Diet.sorted(natural)) { diet in
                    Badge(text: diet.shortTitle, symbol: diet.symbol, tint: Theme.good)
                }
            }
        }
    }

    private func adaptationNote(_ match: RecipeMatch) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Az étrendedhez igazítva", systemImage: "arrow.triangle.swap")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.warn)
            ForEach(match.substitutions) { evaluation in
                if let sub = evaluation.substitution {
                    Text("\(evaluation.ingredient.name) helyett: \(evaluation.effectiveName). \(sub.note)")
                        .font(.footnote)
                }
            }
            ForEach(match.omitted) { evaluation in
                Text("Elhagyható: \(evaluation.ingredient.name) (nem fér az étrendbe).")
                    .font(.footnote)
            }
            Text("Súlyos allergia vagy cöliákia esetén ellenőrizd a termékek címkéjét.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func translationBox(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ez a recept angol nyelvű.", systemImage: "globe")
                .font(.subheadline.bold())
            if model.translating.contains(recipe.id) {
                HStack {
                    ProgressView()
                    Text("Fordítás…").foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await model.translate(recipe.id) }
                } label: {
                    Label("Fordítás magyarra", systemImage: "character.bubble")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func ingredientsSection(_ match: RecipeMatch, scale: Double, servings shown: Int, baseServings: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hozzávalók").font(.title3.bold())
                Spacer()
                Stepper(value: Binding(get: { shown }, set: { servings = $0 }), in: 1...24) {
                    Text("\(shown) adag").font(.subheadline)
                }
                .fixedSize()
            }
            VStack(spacing: 0) {
                ForEach(match.evaluations) { evaluation in
                    ingredientRow(evaluation, scale: scale)
                    if evaluation.index != match.evaluations.last?.index {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

            if match.missingCount > 0 {
                Button {
                    model.addMissingToShopping(match, scale: scale)
                    addedToList = true
                } label: {
                    Label(addedToList ? "Hozzáadva a listához" : "Hiányzók a bevásárlólistára (\(match.missingCount))",
                          systemImage: addedToList ? "checkmark" : "cart.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(addedToList)
            }
        }
    }

    private func ingredientRow(_ evaluation: IngredientEvaluation, scale: Double) -> some View {
        let ingredient = evaluation.ingredient
        var quantity = QuantityFormatter.format(amount: ingredient.amount, unit: ingredient.unit, scale: scale)
        if quantity.isEmpty, let raw = ingredient.rawMeasure { quantity = raw }
        let status = statusInfo(evaluation.availability)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(evaluation.effectiveName + (ingredient.optional ? " (elhagyható)" : ""))
                    .strikethrough(evaluation.availability == .omitted)
                if evaluation.isSubstituted {
                    Text("helyette: \(ingredient.name)").font(.caption).foregroundStyle(.secondary)
                }
                if let note = ingredient.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(quantity).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityValue(status.label)
    }

    private func statusInfo(_ availability: Availability) -> (symbol: String, tint: Color, label: String) {
        switch availability {
        case .have: return ("checkmark.circle.fill", Theme.good, "van otthon")
        case .staple: return ("house.fill", .secondary, "alapvető, feltételezzük")
        case .missing: return ("cart", Theme.warn, "hiányzik")
        case .omitted: return ("minus.circle", .secondary, "elhagyva")
        case .unresolved: return ("questionmark.circle", .secondary, "nem azonosított")
        case .blocked: return ("xmark.circle.fill", Theme.bad, "nem megfelelő")
        }
    }

    private func stepsSection(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Elkészítés").font(.title3.bold())
                Spacer()
                Button {
                    cooking = true
                } label: {
                    Label("Főzés", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Theme.paprika, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.text)
                        if let minutes = step.timerMinutes {
                            Badge(text: "\(minutes) perc", symbol: "timer")
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(index + 1). lépés. \(step.text)")
            }
        }
    }

    @ViewBuilder
    private func footer(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if recipe.source == .mealdb {
                Text(recipe.language == "hu"
                     ? "Gépi fordítás, hibákat tartalmazhat. Forrás: TheMealDB."
                     : "Forrás: TheMealDB.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = recipe.sourceURL {
                    Link("Eredeti recept megnyitása", destination: url).font(.caption)
                }
                Text("A letöltött receptek hozzávalóinál az étrendi ellenőrzés csak az azonosított alapanyagokra vonatkozik.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func shareText(_ match: RecipeMatch, scale: Double) -> String {
        var lines = [match.recipe.title, ""]
        lines.append("Hozzávalók:")
        for evaluation in match.evaluations where evaluation.availability != .omitted {
            let quantity = QuantityFormatter.format(amount: evaluation.ingredient.amount,
                                                    unit: evaluation.ingredient.unit, scale: scale)
            lines.append("- " + (quantity.isEmpty ? "" : quantity + " ") + evaluation.effectiveName)
        }
        lines.append("")
        lines.append("Elkészítés:")
        for (index, step) in match.recipe.steps.enumerated() {
            lines.append("\(index + 1). \(step.text)")
        }
        lines.append("")
        lines.append("Fincsi")
        return lines.joined(separator: "\n")
    }
}
