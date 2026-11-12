import Foundation

/// Az app saját hibái, magyar, felhasználónak mutatható üzenetekkel.
public enum FincsiError: LocalizedError, Equatable {
    case resourceMissing(String)
    case network(String)
    case badResponse
    case rateLimited
    case quotaExceeded
    case translationNotConfigured
    case translationFailed(String)
    case storage(String)

    public var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            return "Hiányzó beépített adatfájl: \(name)."
        case .network(let detail):
            return "Nincs hálózati kapcsolat, vagy a szolgáltatás nem érhető el. \(detail)"
        case .badResponse:
            return "A szolgáltatás váratlan választ adott."
        case .rateLimited:
            return "A szolgáltatás átmenetileg túl sok kérést kapott, próbáld újra később."
        case .quotaExceeded:
            return "A fordítás napi kerete elfogyott. Add meg a saját DeepL kulcsodat a Beállításokban, vagy próbáld később."
        case .translationNotConfigured:
            return "Nincs elérhető fordítószolgáltatás."
        case .translationFailed(let detail):
            return "A fordítás nem sikerült. \(detail)"
        case .storage(let detail):
            return "A mentés nem sikerült. \(detail)"
        }
    }
}
