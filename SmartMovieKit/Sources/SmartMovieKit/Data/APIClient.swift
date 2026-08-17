import Foundation

public enum APIError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case rateLimited(retryAfter: Int?)
    case server(status: Int, requestID: String?)
    case decoding(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: String(localized: "The request URL is invalid.", bundle: .module)
        case .invalidResponse: String(localized: "The server returned an invalid response.", bundle: .module)
        case .unauthorized: String(localized: "The service is not configured correctly.", bundle: .module)
        case .notFound: String(localized: "This title is no longer available.", bundle: .module)
        case .rateLimited: String(localized: "Too many requests. Please try again shortly.", bundle: .module)
        case .server: String(localized: "The service is temporarily unavailable.", bundle: .module)
        case .decoding: String(localized: "Some movie information could not be read.", bundle: .module)
        case .transport: String(localized: "Check your internet connection and try again.", bundle: .module)
        }
    }
}

public protocol ClientIDProviding: Sendable {
    func clientID() async -> String
}

public actor InstallationClientID: ClientIDProviding {
    private let defaults: UserDefaults
    private let key = "SmartMovie.InstallationClientID"

    public init(suiteName: String? = nil) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func clientID() -> String {
        if let existing = defaults.string(forKey: key), UUID(uuidString: existing) != nil {
            return existing
        }
        let value = UUID().uuidString.lowercased()
        defaults.set(value, forKey: key)
        return value
    }
}

public actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let clientIDProvider: any ClientIDProviding
    private let decoder: JSONDecoder
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        clientIDProvider: any ClientIDProviding = InstallationClientID(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.clientIDProvider = clientIDProvider
        self.sleep = sleep
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    public func get<Response: Decodable & Sendable>(
        _ path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        guard var components = URLComponents(
            url: baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(await clientIDProvider.clientID(), forHTTPHeaderField: "X-SmartMovie-Client")

        var lastError: Error?
        for attempt in 0 ... 2 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                if (200 ... 299).contains(http.statusCode) {
                    do {
                        return try decoder.decode(Response.self, from: data)
                    } catch {
                        throw APIError.decoding(error.localizedDescription)
                    }
                }

                let payload = try? decoder.decode(ErrorEnvelope.self, from: data)
                switch http.statusCode {
                case 401, 403: throw APIError.unauthorized
                case 404: throw APIError.notFound
                case 429:
                    let retryAfter = payload?.error.retryAfter
                        ?? http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                    if attempt < 2 {
                        try await sleep(.seconds(retryAfter ?? (attempt + 1)))
                        continue
                    }
                    throw APIError.rateLimited(retryAfter: retryAfter)
                case 500 ... 599:
                    if attempt < 2 {
                        try await sleep(.milliseconds(300 * (attempt + 1)))
                        continue
                    }
                    throw APIError.server(status: http.statusCode, requestID: payload?.error.requestId)
                default:
                    throw APIError.server(status: http.statusCode, requestID: payload?.error.requestId)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as APIError {
                throw error
            } catch {
                lastError = APIError.transport(error.localizedDescription)
                if attempt < 2 {
                    try await sleep(.milliseconds(300 * (attempt + 1)))
                }
            }
        }
        throw lastError ?? APIError.invalidResponse
    }
}

struct ErrorEnvelope: Decodable {
    let error: ErrorBody
}

struct ErrorBody: Decodable {
    let code: String
    let message: String
    let requestId: String?
    let retryAfter: Int?
}
