import SwiftUI
import FincsiKit

struct PantryView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case have = "Van otthon"
        case exclude = "Nem kérem"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .have
    @State private var search = ""
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                Section("Étrend") {
                    ForEach(Diet.allCases) { diet in
                        Toggle(isOn: dietBinding(diet)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(diet.title, systemImage: diet.symbol)
                                Text(diet.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Picker("Mit jelölsz?", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Label("\(model.data.pantry.count) otthon", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.good)
                        Spacer()
                        Label("\(model.data.excluded.count) kizárva", systemImage: "nosign")
                            .foregroundStyle(Theme.bad)
                    }
                    .font(.footnote)
                    .accessibilityElement(children: .combine)
                } footer: {
                    Text(mode == .have
                         ? "Koppints arra, ami megvan otthon. Só, víz és étolaj alapból feltételezett (a Beállításokban kikapcsolható)."
                         : "Koppints arra, amit nem szeretsz vagy nem ehetsz. Az ilyen alapanyagot tartalmazó receptek nem jelennek meg.")
                }

                if let catalog = model.catalog {
                    if search.trimmingCharacters(in: .whitespaces).isEmpty {
                        ForEach(catalog.categories.sorted { $0.order < $1.order }) { category in
                            let items = catalog.ingredients(in: category.id)
                            if !items.isEmpty {
                                Section(category.name) {
                                    ForEach(items) { row($0) }
                                }
                            }
                        }
                    } else {
                        let results = catalog.search(search, limit: 60)
                        Section("Találatok") {
                            if results.isEmpty {
                                Text("Nincs ilyen alapanyag a listában.").foregroundStyle(.secondary)
                            }
                            ForEach(results) { row($0) }
                        }
                    }
                }
            }
            .navigationTitle("Kamra")
            .searchable(text: $search, prompt: "Alapanyag keresése")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Kamra ürítése", role: .destructive) { confirmClear = true }
                            .disabled(model.data.pantry.isEmpty)
                        Button("Kizárások törlése", role: .destructive) {
                            model.update { $0.excluded = [] }
                        }
                        .disabled(model.data.excluded.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Több művelet")
                }
            }
            .confirmationDialog("Kiüríted a kamrát?", isPresented: $confirmClear) {
                Button("Ürítés", role: .destructive) { model.update { $0.pantry = [] } }
                Button("Mégse", role: .cancel) {}
            }
        }
    }

    private func row(_ ingredient: Ingredient) -> some View {
        let have = model.data.pantry.contains(ingredient.id)
        let excluded = model.data.excluded.contains(ingredient.id)
        return Button {
            model.update { data in
                if mode == .have {
                    data.setInPantry(ingredient.id, !have)
                } else {
                    data.setExcluded(ingredient.id, !excluded)
                }
            }
        } label: {
            HStack {
                Text(ingredient.name).foregroundStyle(.primary)
                if ingredient.staple && model.data.settings.assumeStaples {
                    Text("alap").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if have {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                } else if excluded {
                    Image(systemName: "nosign").foregroundStyle(Theme.bad)
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(have ? "van otthon" : (excluded ? "kizárva" : "nincs jelölve"))
        .accessibilityAddTraits(.isButton)
    }

    private func dietBinding(_ diet: Diet) -> Binding<Bool> {
        Binding(
            get: { model.data.diets.contains(diet) },
            set: { on in
                model.update { data in
                    if on { data.diets.insert(diet) } else { data.diets.remove(diet) }
                }
            }
        )
    }
}
