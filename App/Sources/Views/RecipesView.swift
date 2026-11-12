import SwiftUI
import FincsiKit

struct RecipesView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = RecipeFilter()
    @State private var path: [String] = []

    private var usableAll: [RecipeMatch] {
        model.matches.filter { match in
            guard match.verdict.isUsable else { return false }
            if filter.favoritesOnly && !model.data.isFavorite(match.recipe.id) { return false }
            if let course = filter.course, match.recipe.course != course { return false }
            if !filter.query.isEmpty {
                let q = filter.query
                let inTitle = match.recipe.title.localizedStandardContains(q)
                let inIngredients = match.recipe.ingredients.contains { $0.name.localizedStandardContains(q) }
                if !inTitle && !inIngredients { return false }
            }
            return true
        }
    }

    private var rejected: [RecipeMatch] {
        model.matches.filter { !$0.verdict.isUsable }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                controls
                if model.data.pantry.isEmpty && filter.pantryMode {
                    Section {
                        Label("A Kamra fülön jelöld be, mi van otthon, és itt azonnal látod, mit főzhetsz. Addig az összes megfelelő receptet mutatjuk.",
                              systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                content
                filteredOut
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Receptek")
            .searchable(text: $filter.query, prompt: "Recept vagy alapanyag")
            .navigationDestination(for: String.self) { id in
                RecipeDetailView(recipeID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        surprise()
                    } label: {
                        Label("Meglepj!", systemImage: "dice")
                    }
                    .accessibilityHint("Véletlenszerű recept a kamrád alapján")
                }
            }
            .overlay {
                if usableAll.isEmpty {
                    ContentUnavailableView("Nincs találat", systemImage: "magnifyingglass",
                                           description: Text("Próbálj másik szűrőt, vagy lazíts az étrendi beállításokon."))
                }
            }
        }
    }

    // MARK: Vezérlők

    private var controls: some View {
        Section {
            Picker("Mód", selection: $filter.pantryMode) {
                Text("Kamrám alapján").tag(true)
                Text("Összes").tag(false)
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("Mind", selected: filter.course == nil && !filter.favoritesOnly) {
                        filter.course = nil
                        filter.favoritesOnly = false
                    }
                    chip("Kedvencek", symbol: "heart.fill", selected: filter.favoritesOnly) {
                        filter.favoritesOnly.toggle()
                    }
                    ForEach(Course.allCases) { course in
                        chip(course.title, symbol: course.symbol, selected: filter.course == course) {
                            filter.course = (filter.course == course) ? nil : course
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))

            if !model.data.diets.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Diet.sorted(model.data.diets)) { diet in
                        Badge(text: diet.shortTitle, symbol: diet.symbol, tint: Theme.good)
                    }
                }
            }
        }
    }

    private func chip(_ title: String, symbol: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol = symbol { Image(systemName: symbol).imageScale(.small) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? Theme.paprika : Color(.tertiarySystemFill), in: Capsule())
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Tartalom

    @ViewBuilder
    private var content: some View {
        let usable = usableAll
        let limit = model.data.settings.maxMissing
        if filter.pantryMode && !model.data.pantry.isEmpty {
            let ready = usable.filter { $0.missingCount == 0 }
            let almost = usable.filter { $0.missingCount >= 1 && $0.missingCount <= limit }
            if let idea = dailyIdea(ready: ready, almost: almost) {
                Section("Mai ötlet") {
                    row(idea)
                }
            }
            if !ready.isEmpty {
                Section("Most megfőzhető (\(ready.count))") {
                    ForEach(ready) { row($0) }
                }
            }
            if !almost.isEmpty {
                Section("Majdnem megvan – legfeljebb \(limit) hiányzó (\(almost.count))") {
                    ForEach(almost) { row($0) }
                }
            }
        } else {
            let sorted = usable.sorted { $0.recipe.title.localizedCompare($1.recipe.title) == .orderedAscending }
            Section("\(sorted.count) recept") {
                ForEach(sorted) { row($0) }
            }
        }
    }

    @ViewBuilder
    private var filteredOut: some View {
        let list = rejected
        if !list.isEmpty && filter.query.isEmpty && filter.course == nil && !filter.favoritesOnly {
            Section {
                DisclosureGroup("\(list.count) recept kiszűrve az étrended vagy a kizárásaid miatt") {
                    ForEach(list.prefix(60)) { match in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.recipe.title).font(.subheadline)
                            Text(reasonText(match)).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func reasonText(_ match: RecipeMatch) -> String {
        switch match.verdict {
        case .excluded:
            return "Nem kérem: " + match.blockers.joined(separator: ", ")
        case .dietConflict:
            return "Nem fér az étrendbe, nincs csere: " + match.blockers.joined(separator: ", ")
        case .uncertain:
            return "Nem ellenőrizhető az étrendi megfelelés (ismeretlen hozzávaló). A Beállításokban megengedheted."
        default:
            return ""
        }
    }

    private func row(_ match: RecipeMatch) -> some View {
        NavigationLink(value: match.recipe.id) {
            RecipeRow(match: match, favorite: model.data.isFavorite(match.recipe.id))
        }
        .swipeActions(edge: .trailing) {
            Button {
                model.update { $0.toggleFavorite(match.recipe.id) }
            } label: {
                Label("Kedvenc", systemImage: "heart")
            }
            .tint(Theme.paprika)
        }
    }

    // MARK: Ötletek

    private func dailyIdea(ready: [RecipeMatch], almost: [RecipeMatch]) -> RecipeMatch? {
        let pool = ready.isEmpty ? almost : ready
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return pool[day % pool.count]
    }

    private func surprise() {
        let limit = model.data.settings.maxMissing
        let usable = model.matches.filter { $0.verdict.isUsable }
        let pool: [RecipeMatch]
        if filter.pantryMode && !model.data.pantry.isEmpty {
            let ready = usable.filter { $0.missingCount == 0 }
            pool = ready.isEmpty ? usable.filter { $0.missingCount <= limit } : ready
        } else {
            pool = usable
        }
        if let pick = pool.randomElement() {
            path.append(pick.recipe.id)
        }
    }
}

struct RecipeRow: View {
    let match: RecipeMatch
    let favorite: Bool

    var body: some View {
        HStack(spacing: 12) {
            RecipeThumb(recipe: match.recipe)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(match.recipe.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(match.recipe.course.title)
                    if match.recipe.totalMinutes > 0 {
                        Text("· \(minutesText(match.recipe.totalMinutes))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    availability
                    if match.substitutionCount > 0 {
                        Badge(text: "\(match.substitutionCount) csere", symbol: "arrow.triangle.swap", tint: Theme.warn)
                    }
                    if match.recipe.needsTranslation {
                        Badge(text: "angol", symbol: "globe", tint: .secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            if favorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Theme.paprika)
                    .accessibilityLabel("Kedvenc")
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var availability: some View {
        if match.missingCount == 0 {
            Badge(text: "Minden megvan", symbol: "checkmark.circle.fill", tint: Theme.good)
        } else {
            Badge(text: "\(match.missingCount) hiányzik", symbol: "cart", tint: Theme.warn)
        }
    }
}

struct RecipeThumb: View {
    let recipe: Recipe

    var body: some View {
        ZStack {
            Theme.paprika.opacity(0.12)
            Image(systemName: recipe.course.symbol)
                .font(.title3)
                .foregroundStyle(Theme.paprika)
            if let url = recipe.imageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
