import Foundation
import Combine

final class APIClient {
    static let shared = APIClient()

    struct AuthTokens: Codable, Equatable {
        let access: String
        let refresh: String
    }

    struct RegisterResponse: Decodable {
        let id: UUID
        let username: String
        let email: String
        let tokens: AuthTokens
    }

    struct UserProfile: Decodable {
        let id: UUID
        let username: String
        let email: String
    }

    struct SyncStateResponse: Decodable {
        let categories: [Category]
        let todos: [TodoEntry]
        let sessions: [TimeSession]
        let travelTimes: [TravelTimeResponse]?
    }

    struct TravelTimeResponse: Decodable {
        let locationKey: String
        let durationMinutes: Int
    }

    var onTokensChanged: ((AuthTokens?) -> Void)?

    private let baseURL: URL?
    private let sessionLock = NSLock()
    private var tokens: AuthTokens?
    private var inFlightRefresh: AnyPublisher<AuthTokens, Error>?

    var isAuthenticated: Bool { sessionSnapshot() != nil }

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private init() {
        let configuredValue = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        let configuredURL = configuredValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configuredURL,
           !configuredURL.isEmpty,
           !configuredURL.contains("$("),
           let url = URL(string: configuredURL),
           Self.isAllowedBaseURL(url) {
            baseURL = url
        } else {
#if DEBUG
            baseURL = URL(string: "http://127.0.0.1:8000/api/")
#else
            baseURL = nil
#endif
        }
    }

    private static func isAllowedBaseURL(_ url: URL) -> Bool {
#if DEBUG
        return url.scheme == "https" || url.scheme == "http"
#else
        return url.scheme == "https"
#endif
    }

    func setAuthTokens(_ tokens: AuthTokens, notify: Bool = true) {
        sessionLock.lock()
        self.tokens = tokens
        sessionLock.unlock()
        if notify { onTokensChanged?(tokens) }
    }

    func clearAuthTokens(notify: Bool = true) {
        sessionLock.lock()
        tokens = nil
        sessionLock.unlock()
        if notify { onTokensChanged?(nil) }
    }

    func registerAccount(
        username: String,
        email: String,
        password: String
    ) -> AnyPublisher<RegisterResponse, Error> {
        let payload = [
            "username": username,
            "email": email,
            "password": password,
        ]
        return encodedRequest("auth/register/", method: "POST", payload: payload)
    }

    func login(username: String, password: String) -> AnyPublisher<AuthTokens, Error> {
        let payload = ["username": username, "password": password]
        return encodedRequest("auth/token/", method: "POST", payload: payload)
    }

    func fetchProfile() -> AnyPublisher<UserProfile, Error> {
        request("auth/me/")
    }

    func fetchSyncState() -> AnyPublisher<SyncStateResponse, Error> {
        request("sync/")
    }

    func syncTravelTimes(_ travelTimes: [String: Int]) -> AnyPublisher<SyncStateResponse, Error> {
        encodedRequest(
            "sync/",
            method: "POST",
            payload: TravelTimeSyncPayload(locationTravelTimes: travelTimes)
        )
    }

    func logout() -> AnyPublisher<Void, Error> {
        guard let refreshToken = sessionSnapshot()?.refresh else {
            return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        do {
            let body = try jsonEncoder.encode(["refresh": refreshToken])
            return dataRequest(
                "auth/logout/",
                method: "POST",
                body: body,
                mayRefresh: false
            )
            .map { _ in () }
            .eraseToAnyPublisher()
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    func fetchTodos() -> AnyPublisher<[TodoEntry], Error> {
        request("todos/")
    }

    func createTodo(_ todo: TodoEntry) -> AnyPublisher<TodoEntry, Error> {
        encodedRequest("todos/", method: "POST", payload: todo)
    }

    func updateTodo(_ todo: TodoEntry) -> AnyPublisher<TodoEntry, Error> {
        encodedRequest("todos/\(todo.id)/", method: "PUT", payload: todo)
    }

    func deleteTodo(id: UUID) -> AnyPublisher<Void, Error> {
        voidRequest("todos/\(id)/", method: "DELETE")
    }

    func createTimeSession(todoId: UUID, start: Date) -> AnyPublisher<TimeSession, Error> {
        let payload = [
            "todo": todoId.uuidString,
            "start": ISO8601DateFormatter().string(from: start),
        ]
        return encodedRequest("sessions/", method: "POST", payload: payload)
    }

    func finishTimeSession(id: UUID, end: Date) -> AnyPublisher<TimeSession, Error> {
        let payload = ["end": ISO8601DateFormatter().string(from: end)]
        return encodedRequest("sessions/\(id)/", method: "PATCH", payload: payload)
    }

    func deleteTimeSession(id: UUID) -> AnyPublisher<Void, Error> {
        voidRequest("sessions/\(id)/", method: "DELETE")
    }

    func fetchCategories() -> AnyPublisher<[Category], Error> {
        request("categories/")
    }

    func createCategory(_ category: Category) -> AnyPublisher<Category, Error> {
        encodedRequest("categories/", method: "POST", payload: category)
    }

    func updateCategory(_ category: Category) -> AnyPublisher<Category, Error> {
        encodedRequest("categories/\(category.id)/", method: "PUT", payload: category)
    }

    func deleteCategory(id: UUID) -> AnyPublisher<Void, Error> {
        voidRequest("categories/\(id)/", method: "DELETE")
    }

    private func encodedRequest<T: Decodable, Payload: Encodable>(
        _ endpoint: String,
        method: String,
        payload: Payload
    ) -> AnyPublisher<T, Error> {
        do {
            return request(endpoint, method: method, body: try jsonEncoder.encode(payload))
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    private func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: Data? = nil
    ) -> AnyPublisher<T, Error> {
        dataRequest(endpoint, method: method, body: body, mayRefresh: true)
            .decode(type: T.self, decoder: jsonDecoder)
            .eraseToAnyPublisher()
    }

    private func voidRequest(_ endpoint: String, method: String) -> AnyPublisher<Void, Error> {
        dataRequest(endpoint, method: method, body: nil, mayRefresh: true)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    private func dataRequest(
        _ endpoint: String,
        method: String,
        body: Data?,
        mayRefresh: Bool
    ) -> AnyPublisher<Data, Error> {
        guard let request = makeRequest(endpoint: endpoint, method: method, body: body) else {
            return Fail(error: APIError.configuration).eraseToAnyPublisher()
        }

        return URLSession.shared.dataTaskPublisher(for: request)
            .mapError { $0 as Error }
            .tryMap(Self.validatedData)
            .catch { [weak self] error -> AnyPublisher<Data, Error> in
                guard let self,
                      mayRefresh,
                      (error as? APIError)?.statusCode == 401,
                      self.sessionSnapshot()?.refresh.isEmpty == false else {
                    return Fail(error: error).eraseToAnyPublisher()
                }
                return self.refreshSession()
                    .flatMap { _ in
                        self.dataRequest(
                            endpoint,
                            method: method,
                            body: body,
                            mayRefresh: false
                        )
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    private func makeRequest(endpoint: String, method: String, body: Data?) -> URLRequest? {
        guard let url = resolvedURL(for: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken = sessionSnapshot()?.access {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        request.timeoutInterval = 30
        return request
    }

    private func resolvedURL(for endpoint: String) -> URL? {
        guard let baseURL else { return nil }
        let baseString = baseURL.absoluteString.hasSuffix("/")
            ? baseURL.absoluteString
            : baseURL.absoluteString + "/"
        let cleanEndpoint = endpoint.hasPrefix("/")
            ? String(endpoint.dropFirst())
            : endpoint
        return URL(string: cleanEndpoint, relativeTo: URL(string: baseString))?.absoluteURL
    }

    private func refreshSession() -> AnyPublisher<AuthTokens, Error> {
        sessionLock.lock()
        if let inFlightRefresh {
            sessionLock.unlock()
            return inFlightRefresh
        }
        guard let currentTokens = tokens,
              let url = resolvedURL(for: "auth/token/refresh/") else {
            sessionLock.unlock()
            return Fail(error: APIError.configuration).eraseToAnyPublisher()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["refresh": currentTokens.refresh])
        request.timeoutInterval = 30

        let publisher = URLSession.shared.dataTaskPublisher(for: request)
            .mapError { $0 as Error }
            .tryMap(Self.validatedData)
            .decode(type: RefreshResponse.self, decoder: jsonDecoder)
            .map { response in
                AuthTokens(
                    access: response.access,
                    refresh: response.refresh ?? currentTokens.refresh
                )
            }
            .handleEvents(
                receiveOutput: { [weak self] tokens in
                    self?.setAuthTokens(tokens)
                },
                receiveCompletion: { [weak self] completion in
                    self?.finishRefresh(completion: completion)
                },
                receiveCancel: { [weak self] in
                    self?.clearInFlightRefresh()
                }
            )
            .share()
            .eraseToAnyPublisher()
        inFlightRefresh = publisher
        sessionLock.unlock()
        return publisher
    }

    private func finishRefresh(completion: Subscribers.Completion<Error>) {
        clearInFlightRefresh()
        guard case .failure(let error) = completion,
              let statusCode = (error as? APIError)?.statusCode,
              statusCode == 400 || statusCode == 401 else { return }
        clearAuthTokens()
    }

    private func clearInFlightRefresh() {
        sessionLock.lock()
        inFlightRefresh = nil
        sessionLock.unlock()
    }

    private func sessionSnapshot() -> AuthTokens? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return tokens
    }

    private static func validatedData(_ output: URLSession.DataTaskPublisher.Output) throws -> Data {
        guard let response = output.response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(response.statusCode) else {
            let message = serverMessage(from: output.data, statusCode: response.statusCode)
            throw APIError(statusCode: response.statusCode, message: message)
        }
        return output.data
    }

    static func serverMessage(from data: Data, statusCode: Int) -> String {
        let fallback = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        guard data.count <= 64 * 1024,
              let object = try? JSONSerialization.jsonObject(with: data),
              let message = message(from: object),
              !message.isEmpty else {
            return fallback
        }
        return String(message.prefix(600))
    }

    private static func message(from object: Any) -> String? {
        if let message = object as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let messages = object as? [Any] {
            let values = messages.compactMap(message(from:)).filter { !$0.isEmpty }
            return values.isEmpty ? nil : values.joined(separator: " ")
        }
        if let fields = object as? [String: Any] {
            if let detail = fields["detail"], let detailMessage = message(from: detail) {
                return detailMessage
            }
            let values = fields.keys.sorted().compactMap { key -> String? in
                guard let value = fields[key],
                      let fieldMessage = message(from: value),
                      !fieldMessage.isEmpty else { return nil }
                let label = key == "non_field_errors"
                    ? "Error"
                    : key.replacingOccurrences(of: "_", with: " ").capitalized
                return "\(label): \(fieldMessage)"
            }
            return values.isEmpty ? nil : values.joined(separator: " ")
        }
        return nil
    }
}

private struct TravelTimeSyncPayload: Encodable {
    let locationTravelTimes: [String: Int]
}

private struct RefreshResponse: Decodable {
    let access: String
    let refresh: String?
}

struct APIError: LocalizedError {
    let statusCode: Int
    let message: String

    static let configuration = APIError(
        statusCode: 0,
        message: "Cloud sync is not configured in this build."
    )

    var errorDescription: String? {
        statusCode == 0 ? message : "Server error \(statusCode): \(message)"
    }
}
