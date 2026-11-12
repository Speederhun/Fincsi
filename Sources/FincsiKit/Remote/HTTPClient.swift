import Foundation

/// Cserélhető hálózati réteg, hogy a hálózati kód tesztelhető legyen.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public extension HTTPClient {
    func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await send(request)
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 60
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw FincsiError.badResponse
            }
            return (data, http)
        } catch let error as FincsiError {
            throw error
        } catch {
            if (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw FincsiError.network(error.localizedDescription)
        }
    }
}

/// Újrapróbálkozás kapcsolati hibánál, 429-nél és 5xx állapotnál, növekvő várakozással.
public enum Retry {
    public static func perform(attempts: Int = 3, baseDelay: Double = 0.6,
                               _ operation: () async throws -> (Data, HTTPURLResponse)) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error = FincsiError.badResponse
        for attempt in 0..<max(1, attempts) {
            do {
                let (data, response) = try await operation()
                if response.statusCode == 429 || (500...599).contains(response.statusCode) {
                    lastError = response.statusCode == 429 ? FincsiError.rateLimited : FincsiError.badResponse
                } else {
                    return (data, response)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
            if attempt < attempts - 1 {
                let delay = baseDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        throw lastError
    }
}
