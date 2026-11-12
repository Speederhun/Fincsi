import SwiftUI
import FincsiKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var deepL = ""
    @State private var confirmReset = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Só, bors, víz, olaj mindig van", isOn: settingBinding(\.assumeStaples))
                    Toggle("Ismeretlen hozzávalójú receptek is", isOn: settingBinding(\.allowUncertain))
                    Stepper(value: settingBinding(\.maxMissing), in: 1...8) {
                        Text("„Majdnem megvan”: legfeljebb \(model.data.settings.maxMissing) hiányzó")
                    }
                } header: {
                    Text("Ajánlások")
                } footer: {
                    Text("Étrend mellett az ismeretlen hozzávalójú (letöltött) receptek alapból rejtve maradnak, mert az étrendi megfelelésük nem ellenőrizhető.")
                }

                Section {
                    LabeledContent("Letöltött receptek", value: "\(model.remoteCount)")
                    if let date = model.lastSync {
                        LabeledContent("Utolsó frissítés", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button {
                        Task { await model.syncRecipes() }
                    } label: {
                        if model.syncState == .running {
                            HStack { ProgressView(); Text("Letöltés…") }
                        } else {
                            Label("Receptek letöltése (TheMealDB)", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(model.syncState == .running)
                    syncStatus
                    Toggle("Automatikus fordítás megnyitáskor", isOn: settingBinding(\.autoTranslate))
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("Letöltött receptek és fordítások törlése", systemImage: "trash")
                    }
                    .disabled(model.remoteCount == 0)
                } header: {
                    Text("További receptek")
                } footer: {
                    Text("A letöltött receptek angolul érkeznek, és gépi fordítással magyarra fordíthatók. Ez nem tökéletes, ezért a hozzávalók és a lépések ellenőrzése javasolt.")
                }

                Section {
                    SecureField("DeepL API-kulcs (nem kötelező)", text: $deepL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("MyMemory e-mail (nagyobb napi keret)", text: stringBinding(\.myMemoryEmail))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    TextField("TheMealDB kulcs (alapból: teszt)", text: stringBinding(\.mealDBKey))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Szolgáltatások")
                } footer: {
                    Text("A DeepL kulcs a Kulcstartóban tárolódik, csak a DeepL felé kerül elküldésre. Kulcs nélkül az ingyenes MyMemory fordít, napi kerettel. A TheMealDB nyilvános teszt-kulcsa fejlesztésre való; az App Store-os kiadáshoz támogatói kulcs szükséges.")
                }

                Section("Adatok") {
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label("Kamra, lista és mentések törlése", systemImage: "arrow.counterclockwise")
                    }
                }

                Section("Névjegy") {
                    LabeledContent("Verzió", value: version)
                    Text("A receptek és cserejavaslatok tájékoztató jellegűek. Súlyos élelmiszer-allergia vagy cöliákia esetén mindig ellenőrizd az összetevőket és a termékek címkéjét.")
                        .font(.footnote)
                    Text("Receptek: beépített magyar gyűjtemény és a TheMealDB (themealdb.com). Fordítás: DeepL és MyMemory.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Beállítások")
            .onAppear { deepL = model.deepLKey }
            .onChange(of: deepL) { _, value in
                model.setDeepLKey(value)
            }
            .confirmationDialog("Törlöd a letöltött recepteket és fordításokat?", isPresented: $confirmClear) {
                Button("Törlés", role: .destructive) { Task { await model.clearDownloaded() } }
                Button("Mégse", role: .cancel) {}
            }
            .confirmationDialog("Törlöd a kamrát, a listát és a mentéseket?", isPresented: $confirmReset) {
                Button("Törlés", role: .destructive) { model.resetAllData() }
                Button("Mégse", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var syncStatus: some View {
        switch model.syncState {
        case .finished(let text):
            Text(text).font(.footnote).foregroundStyle(Theme.good)
        case .failed(let text):
            Text(text).font(.footnote).foregroundStyle(Theme.bad)
        default:
            EmptyView()
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func settingBinding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { model.data.settings[keyPath: keyPath] },
            set: { value in model.update { $0.settings[keyPath: keyPath] = value } }
        )
    }

    private func stringBinding(_ keyPath: WritableKeyPath<AppSettings, String>) -> Binding<String> {
        settingBinding(keyPath)
    }
}
