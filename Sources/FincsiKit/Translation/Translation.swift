import Foundation

/// Angolról magyarra fordító szolgáltatás.
public protocol TextTranslator: Sendable {
    var name: String { get }
    func translate(_ texts: [String]) async throws -> [String]
}

// MARK: - Darabolás

public enum TextChunker {
    /// Mondathatáron darabol, hogy minden rész legfeljebb `maxLength` karakter legyen.
    public static func split(_ text: String, maxLength: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        if trimmed.count <= maxLength { return [trimmed] }

        var sentences: [String] = []
        var current = ""
        for ch in trimmed {
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                sentences.append(current)
                current = ""
            }
        }
        if !current.isEmpty { sentences.append(current) }

        var chunks: [String] = []
        var buffer = ""
        func flush() {
            let cleaned = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { chunks.append(cleaned) }
            buffer = ""
        }
        for sentence in sentences {
            if sentence.count > maxLength {
                flush()
                chunks.append(contentsOf: hardSplit(sentence, maxLength: maxLength))
                continue
            }
            if buffer.count + sentence.count > maxLength {
                flush()
            }
            buffer += sentence
        }
        flush()
        return chunks
    }

    /// Szóhatáron darabol, ha egy mondat önmagában is túl hosszú.
    static func hardSplit(_ text: String, maxLength: Int) -> [String] {
        var chunks: [String] = []
        var buffer = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            let piece = String(word)
            if piece.count > maxLength {
                if !buffer.isEmpty {
                    chunks.append(buffer)
                    buffer = ""
                }
                var rest = Substring(piece)
                while rest.count > maxLength {
                    chunks.append(String(rest.prefix(maxLength)))
                    rest = rest.dropFirst(maxLength)
                }
                buffer = String(rest)
                continue
            }
            if buffer.isEmpty {
                buffer = piece
            } else if buffer.count + 1 + piece.count <= maxLength {
                buffer += " " + piece
            } else {
                chunks.append(buffer)
                buffer = piece
            }
        }
        if !buffer.isEmpty { chunks.append(buffer) }
        return chunks
    }
}

enum HTMLEntities {
    static func decode(_ text: String) -> String {
        var result = text
        let pairs: [(String, String)] = [
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "),
            ("&amp;", "&")
        ]
        for (entity, replacement) in pairs {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}

// MARK: - DeepL

public struct DeepLTranslator: TextTranslator {
    public let name = "DeepL"
    private let http: HTTPClient
    private let apiKey: String

    public init(http: HTTPClient, apiKey: String) {
        self.http = http
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Response: Decodable {
        struct Item: Decodable { let text: String }
        let translations: [Item]
    }

    var endpoint: URL? {
        let host = apiKey.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        return URL(string: "https://\(host)/v2/translate")
    }

    public func translate(_ texts: [String]) async throws -> [String] {
        if texts.isEmpty { return [] }
        if apiKey.isEmpty { throw FincsiError.translationNotConfigured }
        guard let url = endpoint else { throw FincsiError.badResponse }

        var output: [String] = []
        var start = 0
        while start < texts.count {
            let end = min(start + 40, texts.count)
            let batch = Array(texts[start..<end])
            start = end

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["text": batch, "source_lang": "EN", "target_lang": "HU"]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await Retry.perform { try await http.send(request) }
            switch response.statusCode {
            case 200:
                break
            case 403:
                throw FincsiError.translationFailed("A DeepL kulcs érvénytelen.")
            case 456:
                throw FincsiError.quotaExceeded
            case 429:
                throw FincsiError.rateLimited
            default:
                throw FincsiError.badResponse
            }
            guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
                  decoded.translations.count == batch.count else {
                throw FincsiError.badResponse
            }
            output.append(contentsOf: decoded.translations.map { $0.text })
        }
        return output
    }
}

// MARK: - MyMemory (kulcs nélkül)

public struct MyMemoryTranslator: TextTranslator {
    public let name = "MyMemory"
    public static let maxChunk = 450
    private let http: HTTPClient
    private let email: String?

    public init(http: HTTPClient, email: String? = nil) {
        self.http = http
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private struct Response: Decodable {
        struct Payload: Decodable { let translatedText: String? }
        let responseData: Payload?
        let quotaFinished: Bool?
        let status: Int?

        enum CodingKeys: String, CodingKey {
            case responseData
            case quotaFinished
            case responseStatus
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            responseData = try container.decodeIfPresent(Payload.self, forKey: .responseData)
            quotaFinished = try container.decodeIfPresent(Bool.self, forKey: .quotaFinished)
            if let number = try? container.decodeIfPresent(Int.self, forKey: .responseStatus) {
                status = number
            } else if let text = try? container.decodeIfPresent(String.self, forKey: .responseStatus) {
                status = Int(text)
            } else {
                status = nil
            }
        }
    }

    func requestURL(for text: String) -> URL? {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        var items = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "en|hu")
        ]
        if let email = email {
            items.append(URLQueryItem(name: "de", value: email))
        }
        components?.queryItems = items
        return components?.url
    }

    public func translate(_ texts: [String]) async throws -> [String] {
        var output: [String] = []
        for text in texts {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output.append(text)
                continue
            }
            if text.count > 500 {
                throw FincsiError.translationFailed("A szöveg túl hosszú egyetlen kéréshez.")
            }
            guard let url = requestURL(for: text) else { throw FincsiError.badResponse }
            let (data, response) = try await Retry.perform { try await http.get(url) }
            if response.statusCode == 429 { throw FincsiError.quotaExceeded }
            guard response.statusCode == 200 else { throw FincsiError.badResponse }
            guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                throw FincsiError.badResponse
            }
            if decoded.quotaFinished == true || decoded.status == 429 {
                throw FincsiError.quotaExceeded
            }
            guard let translated = decoded.responseData?.translatedText, !translated.isEmpty else {
                throw FincsiError.badResponse
            }
            if translated.uppercased().hasPrefix("MYMEMORY WARNING") {
                throw FincsiError.quotaExceeded
            }
            output.append(HTMLEntities.decode(translated))
        }
        return output
    }
}

// MARK: - Recept fordítása

public struct TranslatedRecipe: Codable, Hashable, Sendable {
    public var recipeID: String
    public var title: String
    public var steps: [String]
    /// Az azonosítatlan alapanyagok fordítása az eredeti név szerint.
    public var ingredientNames: [String: String]
    public var translator: String
    public var date: Date

    public init(recipeID: String, title: String, steps: [String], ingredientNames: [String: String],
                translator: String, date: Date = Date()) {
        self.recipeID = recipeID
        self.title = title
        self.steps = steps
        self.ingredientNames = ingredientNames
        self.translator = translator
        self.date = date
    }
}

public extension Recipe {
    /// A fordítást ráhelyezi a receptre. Az időzítők és az alapanyag-azonosítók megmaradnak.
    func applying(_ translation: TranslatedRecipe) -> Recipe {
        var copy = self
        if !translation.title.isEmpty {
            copy.title = translation.title
        }
        if translation.steps.count == steps.count {
            for index in steps.indices where !translation.steps[index].isEmpty {
                copy.steps[index].text = translation.steps[index]
            }
        }
        for index in copy.ingredients.indices where copy.ingredients[index].ingredientID == nil {
            let original = copy.ingredients[index].name
            if let translated = translation.ingredientNames[original], !translated.isEmpty {
                copy.ingredients[index].name = translated
            }
        }
        copy.language = "hu"
        return copy
    }
}

public struct RecipeTranslator: Sendable {
    private let translators: [TextTranslator]

    /// A fordítók sorrendben próbálkoznak; az első sikeres eredményt használjuk.
    public init(translators: [TextTranslator]) {
        self.translators = translators
    }

    public func translate(_ recipe: Recipe) async throws -> TranslatedRecipe {
        if translators.isEmpty { throw FincsiError.translationNotConfigured }

        // Darabok: cím, lépések, azonosítatlan alapanyagnevek.
        var pieces: [String] = [recipe.title]
        pieces.append(contentsOf: recipe.steps.map { $0.text })
        var unresolved: [String] = []
        for ingredient in recipe.ingredients where ingredient.ingredientID == nil {
            if !unresolved.contains(ingredient.name) { unresolved.append(ingredient.name) }
        }
        pieces.append(contentsOf: unresolved)

        var chunks: [String] = []
        var owner: [Int] = []
        for (index, piece) in pieces.enumerated() {
            for chunk in TextChunker.split(piece, maxLength: MyMemoryTranslator.maxChunk) {
                chunks.append(chunk)
                owner.append(index)
            }
        }
        if chunks.isEmpty { throw FincsiError.translationFailed("Nincs mit fordítani.") }

        var lastError: Error = FincsiError.translationNotConfigured
        for translator in translators {
            do {
                let translated = try await translator.translate(chunks)
                if translated.count != chunks.count {
                    throw FincsiError.badResponse
                }
                var assembled = Array(repeating: "", count: pieces.count)
                for (position, text) in translated.enumerated() {
                    let index = owner[position]
                    assembled[index] = assembled[index].isEmpty ? text : assembled[index] + " " + text
                }
                let title = assembled[0]
                let steps = Array(assembled[1..<(1 + recipe.steps.count)])
                var names: [String: String] = [:]
                for (offset, original) in unresolved.enumerated() {
                    let translatedName = assembled[1 + recipe.steps.count + offset]
                    if !translatedName.isEmpty { names[original] = translatedName }
                }
                return TranslatedRecipe(recipeID: recipe.id, title: title, steps: steps, ingredientNames: names,
                                        translator: translator.name)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        if let known = lastError as? FincsiError {
            throw known
        }
        throw FincsiError.translationFailed(lastError.localizedDescription)
    }
}
