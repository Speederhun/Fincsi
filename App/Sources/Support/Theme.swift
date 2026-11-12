import SwiftUI
import FincsiKit

enum Theme {
    static let paprika = Color.accentColor
    static let good = Color(red: 0.20, green: 0.55, blue: 0.30)
    static let warn = Color(red: 0.85, green: 0.55, blue: 0.10)
    static let bad = Color(red: 0.75, green: 0.18, blue: 0.15)
    static let card = Color(.secondarySystemGroupedBackground)
}

extension Course {
    var symbol: String {
        switch self {
        case .leves: return "cup.and.saucer"
        case .fozelek: return "leaf"
        case .foetel: return "fork.knife"
        case .tesztaetel: return "takeoutbag.and.cup.and.straw"
        case .koret: return "carrot"
        case .desszert: return "birthday.cake"
        case .reggeli: return "sun.max"
        case .egyeb: return "sparkles"
        }
    }
}

extension Diet {
    var shortTitle: String {
        switch self {
        case .glutenFree: return "Gluténmentes"
        case .vegan: return "Vegán"
        case .vegetarian: return "Vegetáriánus"
        case .lactoseFree: return "Laktózmentes"
        case .nutFree: return "Dió nélkül"
        }
    }

    var symbol: String {
        switch self {
        case .glutenFree: return "wheat"
        case .vegan: return "leaf.fill"
        case .vegetarian: return "carrot.fill"
        case .lactoseFree: return "drop"
        case .nutFree: return "allergens"
        }
    }
}

func minutesText(_ minutes: Int) -> String {
    if minutes <= 0 { return "—" }
    if minutes < 60 { return "\(minutes) perc" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours) óra" : "\(hours) óra \(rest) perc"
}

struct Badge: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol = symbol {
                Image(systemName: symbol).imageScale(.small)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
        .foregroundStyle(tint)
    }
}
