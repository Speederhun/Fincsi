import Foundation

/// Ékezet- és kisbetű-független összehasonlításhoz.
public enum TextFolding {
    private static let locale = Locale(identifier: "hu_HU")

    public static func fold(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: locale)
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// Angol alapanyagnevek egységesítése az alias-keresés előtt.
enum NameNormalizer {
    static let descriptors: Set<String> = [
        "fresh", "freshly", "large", "small", "medium", "big", "ripe", "finely", "roughly", "coarsely", "thinly",
        "chopped", "sliced", "diced", "grated", "minced", "peeled", "boneless", "skinless", "free-range",
        "organic", "raw", "extra", "good", "quality", "unsalted", "frozen", "cooked", "whole", "cold", "warm",
        "boiling", "lukewarm", "baby", "pitted", "shredded"
    ]

    /// Kisbetű, zárójeles részek nélkül, egységes szóközökkel.
    static func light(_ text: String) -> String {
        var out = ""
        var depth = 0
        for ch in text.lowercased() {
            if ch == "(" {
                depth += 1
                out.append(" ")
                continue
            }
            if ch == ")" {
                depth = max(0, depth - 1)
                out.append(" ")
                continue
            }
            if depth > 0 { continue }
            if ch == "\u{2019}" || ch == "\u{2018}" {
                out.append("'")
            } else {
                out.append(ch)
            }
        }
        return out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Vessző utáni rész és a leíró szavak (pl. „chopped”, „fresh”) nélkül.
    static func stripped(_ light: String) -> String {
        var head = light
        if let comma = light.firstIndex(of: ",") {
            head = String(light[light.startIndex..<comma])
        }
        let words = head.split(separator: " ").map(String.init).filter { !descriptors.contains($0) }
        return words.joined(separator: " ")
    }

    /// Az utolsó szó egyes számú alakja (egyszerű angol szabályokkal).
    static func singular(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        guard var last = words.popLast() else { return text }
        if last.hasSuffix("ies") && last.count > 4 {
            last = String(last.dropLast(3)) + "y"
        } else if last.hasSuffix("oes") && last.count > 4 {
            last = String(last.dropLast(2))
        } else if (last.hasSuffix("ches") || last.hasSuffix("shes") || last.hasSuffix("sses") || last.hasSuffix("xes")) && last.count > 4 {
            last = String(last.dropLast(2))
        } else if last.hasSuffix("s") && !last.hasSuffix("ss") && last.count > 3 {
            last = String(last.dropLast())
        }
        words.append(last)
        return words.joined(separator: " ")
    }
}
