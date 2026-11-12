import Foundation

public struct ParsedMeasure: Equatable, Sendable {
    /// Magyar egységben kifejezett mennyiség; `nil`, ha nem számszerű.
    public var amount: Double?
    /// Magyar egység (g, kg, dl, ml, l, ek, tk, db, csipet, ...), vagy üres, ha az eredeti szöveget kell mutatni.
    public var unit: String
    public var raw: String

    public init(amount: Double?, unit: String, raw: String) {
        self.amount = amount
        self.unit = unit
        self.raw = raw
    }
}

/// Angol (TheMealDB) mértékek átalakítása magyar egységekre.
public enum MeasureParser {
    private struct UnitRule {
        let unit: String
        let factor: Double
    }

    private static let units: [String: UnitRule] = {
        var map: [String: UnitRule] = [:]
        func add(_ keys: [String], _ unit: String, _ factor: Double = 1) {
            for key in keys {
                map[key] = UnitRule(unit: unit, factor: factor)
            }
        }
        add(["g", "gram", "grams", "gr", "gm"], "g")
        add(["kg", "kilo", "kilogram", "kilograms"], "kg")
        add(["ml", "millilitre", "millilitres", "milliliter", "milliliters"], "ml")
        add(["l", "litre", "litres", "liter", "liters"], "l")
        add(["cl"], "ml", 10)
        add(["dl"], "dl")
        add(["cup", "cups"], "dl", 2.4)
        add(["tbs", "tbsp", "tblsp", "tbls", "tblspn", "tablespoon", "tablespoons", "tb"], "ek")
        add(["tsp", "tspn", "teaspoon", "teaspoons"], "tk")
        add(["oz", "ounce", "ounces"], "g", 28.35)
        add(["lb", "lbs", "pound", "pounds"], "g", 453.6)
        add(["clove", "cloves"], "gerezd")
        add(["slice", "slices"], "szelet")
        add(["pinch", "pinches", "dash", "dashes"], "csipet")
        add(["bunch", "bunches"], "csokor")
        add(["handful", "handfuls"], "marék")
        add(["can", "cans", "tin", "tins"], "doboz")
        add(["sprig", "sprigs", "stalk", "stalks"], "szál")
        add(["large", "medium", "small", "whole", "piece", "pieces", "x", "each"], "db")
        return map
    }()

    private static let tasteWords: [String] = ["to taste", "as needed", "as required", "as desired", "pinch to taste"]
    private static let servingWords: [String] = ["to serve", "for serving", "to garnish", "garnish", "for garnish", "to decorate", "for the garnish"]

    private static let unicodeFractions: [Character: String] = [
        "\u{00BD}": "0.5", "\u{00BC}": "0.25", "\u{00BE}": "0.75", "\u{2153}": "0.333", "\u{2154}": "0.667",
        "\u{215B}": "0.125"
    ]

    public static func parse(_ rawInput: String) -> ParsedMeasure {
        let raw = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return ParsedMeasure(amount: nil, unit: "", raw: "")
        }
        var lower = raw.lowercased()
        for (symbol, replacement) in unicodeFractions {
            lower = lower.replacingOccurrences(of: String(symbol), with: " " + replacement + " ")
        }

        for word in tasteWords where lower.contains(word) {
            return ParsedMeasure(amount: nil, unit: "ízlés szerint", raw: raw)
        }
        for word in servingWords where lower.contains(word) {
            return ParsedMeasure(amount: nil, unit: "tálaláshoz", raw: raw)
        }

        // „175g/6oz” alakban csak az első (metrikus) rész kell; a törtek („1/2”) maradnak.
        var working = lower
        if let slash = working.firstIndex(of: "/") {
            let before = working[working.startIndex..<slash]
            let after = working[working.index(after: slash)...]
            let beforeHasLetters = before.contains { $0.isLetter }
            let afterStartsWithDigit = after.first?.isNumber ?? false
            if beforeHasLetters && afterStartsWithDigit {
                working = String(before)
            }
        }

        var tokens = working.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if tokens.isEmpty {
            return ParsedMeasure(amount: nil, unit: "", raw: raw)
        }

        // „Pinch”, „handful” szám nélkül: egy darabnak számít.
        if let rule = units[tokens[0]], ["csipet", "marék", "csokor"].contains(rule.unit) {
            return ParsedMeasure(amount: 1, unit: rule.unit, raw: raw)
        }

        // Első token: szám, esetleg odaragadt egységgel (200g).
        let (numberPart, gluedRest) = splitNumberAndRest(tokens[0])
        guard var amount = parseNumber(numberPart) else {
            return ParsedMeasure(amount: nil, unit: "", raw: raw)
        }
        tokens.removeFirst()

        // Tartomány: „2-3”.
        var rest = gluedRest
        if rest.hasPrefix("-") || rest.hasPrefix("\u{2013}") {
            let upperText = String(rest.dropFirst())
            let (upperNumber, upperRest) = splitNumberAndRest(upperText)
            if let upper = parseNumber(upperNumber) {
                amount = max(amount, upper)
                rest = upperRest
            }
        }

        // Vegyes szám: „1 1/2”.
        if rest.isEmpty, let next = tokens.first, next.contains("/"), let fraction = parseNumber(next) {
            amount += fraction
            tokens.removeFirst()
        }

        // Egység token.
        var unitToken = rest
        if unitToken.isEmpty, let next = tokens.first {
            unitToken = next
            tokens.removeFirst()
        }
        unitToken = unitToken.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()"))

        if unitToken.isEmpty {
            return ParsedMeasure(amount: amount, unit: "db", raw: raw)
        }
        guard let rule = units[unitToken] else {
            // Ismeretlen egység: az eredeti szöveget mutatjuk, de a szám megmarad, ha csak darabot jelenthet.
            return ParsedMeasure(amount: nil, unit: "", raw: raw)
        }
        return ParsedMeasure(amount: amount * rule.factor, unit: rule.unit, raw: raw)
    }

    private static func splitNumberAndRest(_ token: String) -> (String, String) {
        var number = ""
        var index = token.startIndex
        while index < token.endIndex {
            let ch = token[index]
            if ch.isNumber || ch == "." || ch == "," || ch == "/" {
                number.append(ch)
                index = token.index(after: index)
            } else {
                break
            }
        }
        return (number, String(token[index...]))
    }

    private static func parseNumber(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        if cleaned.isEmpty { return nil }
        if cleaned.contains("/") {
            let parts = cleaned.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let numerator = Double(parts[0].replacingOccurrences(of: ",", with: ".")),
                  let denominator = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
                  denominator != 0 else { return nil }
            return numerator / denominator
        }
        return Double(cleaned.replacingOccurrences(of: ",", with: "."))
    }
}

/// Mennyiségek magyar formázása (tizedesvessző, törtek, kg/l átváltás), adagszám szerinti szorzással.
public enum QuantityFormatter {
    public static func format(amount: Double?, unit: String, scale: Double = 1) -> String {
        guard let amount = amount else {
            return unit
        }
        var value = amount * scale
        var shownUnit = unit

        switch unit {
        case "g":
            if value >= 1000 {
                value /= 1000
                shownUnit = "kg"
            } else if value >= 100 {
                value = (value / 5).rounded() * 5
            } else {
                value = value.rounded()
            }
        case "dkg":
            if value >= 100 {
                value /= 100
                shownUnit = "kg"
            }
        case "ml":
            if value >= 1000 {
                value /= 1000
                shownUnit = "l"
            } else if value >= 100 {
                value = (value / 10).rounded() * 10
            } else {
                value = value.rounded()
            }
        case "dl":
            if value >= 10 {
                value /= 10
                shownUnit = "l"
            } else {
                value = (value * 2).rounded() / 2
                if value == 0 { value = 0.5 }
            }
        default:
            break
        }

        let number = formatNumber(value)
        if shownUnit.isEmpty {
            return number
        }
        return number + " " + shownUnit
    }

    /// Egész, fél, negyed és harmad értékek szépen, egyébként egy tizedesig, vesszővel.
    public static func formatNumber(_ value: Double) -> String {
        if value <= 0 { return "0" }
        let whole = Int(value.rounded(.down))
        let fraction = value - Double(whole)

        func fractionSymbol(_ f: Double) -> String? {
            let table: [(Double, String)] = [(0.25, "\u{00BC}"), (0.333, "\u{2153}"), (0.5, "\u{00BD}"),
                                             (0.667, "\u{2154}"), (0.75, "\u{00BE}")]
            for (target, symbol) in table where abs(f - target) < 0.04 {
                return symbol
            }
            return nil
        }

        if fraction < 0.04 {
            return String(whole)
        }
        if fraction > 0.96 {
            return String(whole + 1)
        }
        if let symbol = fractionSymbol(fraction) {
            return whole == 0 ? symbol : String(whole) + symbol
        }
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }
}

/// Időzítő-javaslat a lépés szövegéből (magyar és angol is).
public enum TimerExtractor {
    private static let pattern = try? NSRegularExpression(
        pattern: "(\\d+(?:[.,]\\d+)?)(?:\\s*(?:-|\\u2013|to|\\u00E9s|vagy)\\s*(\\d+(?:[.,]\\d+)?))?\\s*(perc(?:ig)?|minutes?|mins?|\\u00F3r\\u00E1(?:ig)?|hours?|hrs?)\\b",
        options: [.caseInsensitive]
    )

    public static func minutes(in text: String) -> Int? {
        guard let regex = pattern else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }

        func number(at index: Int) -> Double? {
            let r = match.range(at: index)
            if r.location == NSNotFound { return nil }
            return Double(nsText.substring(with: r).replacingOccurrences(of: ",", with: "."))
        }

        guard let lower = number(at: 1) else { return nil }
        let value = max(lower, number(at: 2) ?? lower)
        let unit = nsText.substring(with: match.range(at: 3)).lowercased()
        let isHours = unit.hasPrefix("h") || unit.hasPrefix("\u{00F3}")
        let minutes = Int((isHours ? value * 60 : value).rounded(.up))
        if minutes <= 0 || minutes > 720 { return nil }
        return minutes
    }
}

/// Nyers utasításszöveg szétbontása lépésekre (letöltött receptekhez).
public enum InstructionParser {
    public static func steps(from text: String) -> [RecipeStep] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var paragraphs: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            let cleaned = cleanLine(String(line))
            if !cleaned.isEmpty {
                paragraphs.append(cleaned)
            }
        }

        // Ha egyetlen hosszú bekezdés van, mondatonként bontjuk, két mondatot egy lépésbe téve.
        if paragraphs.count == 1, let only = paragraphs.first, only.count > 280 {
            paragraphs = chunkSentences(only, perChunk: 2)
        }

        return paragraphs.map { RecipeStep(text: $0, timerMinutes: TimerExtractor.minutes(in: $0)) }
    }

    /// „STEP 3”, „3.”, „3)” előtagok és üres sorok eltávolítása.
    static func cleanLine(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if lower.hasPrefix("step ") {
            let afterStep = text.dropFirst(5)
            if afterStep.allSatisfy({ $0.isNumber || $0 == ":" || $0 == "." || $0 == " " }) {
                return ""
            }
        }
        if lower == "instructions" || lower == "directions" || lower == "method" {
            return ""
        }
        var digits = 0
        for ch in text {
            if ch.isNumber { digits += 1 } else { break }
        }
        if digits > 0 && digits <= 2 {
            let afterDigits = text.dropFirst(digits)
            if let first = afterDigits.first, first == "." || first == ")" {
                text = String(afterDigits.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }
        return text
    }

    static func chunkSentences(_ text: String, perChunk: Int) -> [String] {
        var sentences: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty {
            sentences.append(tail)
        }
        var chunks: [String] = []
        var index = 0
        while index < sentences.count {
            let end = min(index + perChunk, sentences.count)
            chunks.append(sentences[index..<end].joined(separator: " "))
            index = end
        }
        return chunks
    }
}
