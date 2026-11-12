import SwiftUI
import FincsiKit

struct SavedView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case favorites = "Kedvencek"
        case history = "Főztem"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .favorites

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Lista", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                switch tab {
                case .favorites:
                    favorites
                case .history:
                    history
                }
            }
            .navigationTitle("Mentett")
            .navigationDestination(for: String.self) { id in
                RecipeDetailView(recipeID: id)
            }
        }
    }

    @ViewBuilder
    private var favorites: some View {
        let items = model.data.favorites.compactMap { model.match(id: $0) }
        if items.isEmpty {
            Section {
                Text("Még nincs kedvenc recepted. A szív ikonnal vagy balra húzással jelölheted meg őket.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(items) { match in
                    NavigationLink(value: match.recipe.id) {
                        RecipeRow(match: match, favorite: true)
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { items[$0].recipe.id }
                    model.update { data in
                        data.favorites.removeAll { ids.contains($0) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var history: some View {
        if model.data.history.isEmpty {
            Section {
                Text("Itt jelennek meg az elkészített receptek. A Főzés módban az „Elkészült!” gombbal rögzítheted őket.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(model.data.history, id: \.recipeID) { entry in
                    if model.recipe(id: entry.recipeID) != nil {
                        NavigationLink(value: entry.recipeID) {
                            historyRow(entry)
                        }
                    } else {
                        historyRow(entry)
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    model.update { $0.history = [] }
                } label: {
                    Label("Előzmények törlése", systemImage: "trash")
                }
            }
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title)
            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
