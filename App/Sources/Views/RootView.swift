import SwiftUI
import FincsiKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let error = model.bootError {
                ContentUnavailableView("Az app nem indult el", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else {
                TabView {
                    RecipesView()
                        .tabItem { Label("Receptek", systemImage: "book.pages") }
                    PantryView()
                        .tabItem { Label("Kamra", systemImage: "basket") }
                    ShoppingView()
                        .tabItem { Label("Lista", systemImage: "cart") }
                        .badge(model.data.shopping.filter { !$0.checked }.count)
                    SavedView()
                        .tabItem { Label("Mentett", systemImage: "heart") }
                    SettingsView()
                        .tabItem { Label("Beállítások", systemImage: "gearshape") }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { model.bootError == nil && !model.data.onboardingDone },
            set: { _ in }
        )) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .alert("Figyelem", isPresented: Binding(
            get: { model.banner != nil },
            set: { if !$0 { model.banner = nil } }
        )) {
            Button("Rendben", role: .cancel) {}
        } message: {
            Text(model.banner ?? "")
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Add meg, mi van otthon, és a Fincsi receptet javasol belőle. Ha étrendet követsz, a hozzávalókhoz cserét is ajánl.")
                        .font(.body)
                }
                Section("Étrended (később is módosíthatod)") {
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
                    Text("A receptek és a cserejavaslatok tájékoztató jellegűek. Súlyos allergia vagy cöliákia esetén mindig ellenőrizd a termékek címkéjét.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Üdv a Fincsiben")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kezdjük") {
                        model.update { $0.onboardingDone = true }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
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
