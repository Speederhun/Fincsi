import SwiftUI
import FincsiKit

struct ShoppingView: View {
    @Environment(AppModel.self) private var model
    @State private var newItem = ""
    @FocusState private var focused: Bool

    private var open: [ShoppingItem] { model.data.shopping.filter { !$0.checked } }
    private var done: [ShoppingItem] { model.data.shopping.filter { $0.checked } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Új tétel (pl. tej)", text: $newItem)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit(addItem)
                        Button(action: addItem) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Hozzáadás")
                    }
                }

                if model.data.shopping.isEmpty {
                    Section {
                        Text("A lista üres. A receptoldalon a hiányzó hozzávalókat egy koppintással ide teheted.")
                            .foregroundStyle(.secondary)
                    }
                }

                if !open.isEmpty {
                    Section("Megvenni (\(open.count))") {
                        ForEach(open) { row($0) }
                            .onDelete { offsets in delete(offsets, from: open) }
                    }
                }
                if !done.isEmpty {
                    Section("Kipipálva (\(done.count))") {
                        ForEach(done) { row($0) }
                            .onDelete { offsets in delete(offsets, from: done) }
                        Button {
                            model.update { _ = $0.moveCheckedToPantry() }
                        } label: {
                            Label("Kipipáltak a kamrába", systemImage: "basket")
                        }
                        Button(role: .destructive) {
                            model.update { $0.clearCheckedShopping() }
                        } label: {
                            Label("Kipipáltak törlése", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Bevásárlólista")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !open.isEmpty {
                        ShareLink(item: shareText) {
                            Label("Megosztás", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: ShoppingItem) -> some View {
        let quantity = QuantityFormatter.format(amount: item.amount, unit: item.unit)
        return Button {
            model.update { data in
                if let index = data.shopping.firstIndex(where: { $0.id == item.id }) {
                    data.shopping[index].checked.toggle()
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.checked ? Theme.good : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .strikethrough(item.checked)
                        .foregroundStyle(item.checked ? .secondary : .primary)
                    if !item.recipeTitles.isEmpty {
                        Text(item.recipeTitles.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(quantity).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.checked ? "kipipálva" : "nincs kipipálva")
    }

    private func delete(_ offsets: IndexSet, from list: [ShoppingItem]) {
        let ids = Set(offsets.map { list[$0].id })
        model.update { $0.removeShopping(ids: ids) }
    }

    private func addItem() {
        let text = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var matchedID: String? = nil
        var name = text
        if let hit = model.catalog?.search(text, limit: 1).first,
           hit.name.compare(text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            matchedID = hit.id
            name = hit.name
        }
        model.update { $0.addToShopping(ingredientID: matchedID, name: name, amount: nil, unit: "", recipeTitle: nil) }
        newItem = ""
    }

    private var shareText: String {
        let lines = open.map { item -> String in
            let quantity = QuantityFormatter.format(amount: item.amount, unit: item.unit)
            return "- " + (quantity.isEmpty ? "" : quantity + " ") + item.name
        }
        return (["Bevásárlólista (Fincsi)", ""] + lines).joined(separator: "\n")
    }
}
