// APIClient.swift
import Foundation
import Combine

final class APIClient {
    static let shared = APIClient()
    private let baseURL: URL
    private var token: String?

    var isAuthenticated: Bool { token != nil }

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
        let configuredURL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        if let configuredURL,
           !configuredURL.contains("$("),
           let url = URL(string: configuredURL) {
            baseURL = url
        } else {
            baseURL = URL(string: "http://127.0.0.1:8000/api/")!
        }
    }

    // MARK: - Auth

    func setAuthToken(_ token: String) {
        self.token = token
    }

    func clearAuthToken() {
        token = nil
    }

    // MARK: - Generic request helper (for Decodable responses)

    private func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: Data? = nil
    ) -> AnyPublisher<T, Error> {
        var req = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body

        return URLSession.shared.dataTaskPublisher(for: req)
            .tryMap { data, response in
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard (200..<300).contains(http.statusCode) else {
                    let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                        .flatMap { $0["detail"] as? String }
                        ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                    throw APIError(statusCode: http.statusCode, message: message)
                }
                return data
            }
            .decode(type: T.self, decoder: jsonDecoder)
            .eraseToAnyPublisher()
    }

    // MARK: - Fire-and-forget request helper (DELETE / no response body)

    private func voidRequest(
        _ endpoint: String,
        method: String
    ) -> AnyPublisher<Void, Error> {
        var req = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        return URLSession.shared.dataTaskPublisher(for: req)
            .tryMap { _, response in
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return ()
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Todos

    func fetchTodos() -> AnyPublisher<[TodoEntry], Error> {
        request("todos/")
    }

    func createTodo(_ todo: TodoEntry) -> AnyPublisher<TodoEntry, Error> {
        do {
            return request("todos/", method: "POST", body: try jsonEncoder.encode(todo))
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    func updateTodo(_ todo: TodoEntry) -> AnyPublisher<TodoEntry, Error> {
        do {
            return request("todos/\(todo.id)/", method: "PUT", body: try jsonEncoder.encode(todo))
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    func deleteTodo(id: UUID) -> AnyPublisher<Void, Error> {
        voidRequest("todos/\(id)/", method: "DELETE")
    }

    // MARK: - Account Creation & Syncing

    struct AuthTokens: Decodable {
        let access: String
        let refresh: String
    }

    struct RegisterResponse: Decodable {
        let id: UUID
        let username: String
        let email: String
        let tokens: AuthTokens
    }

    struct SyncStateResponse: Decodable {
        let categories: [Category]
        let todos: [TodoEntry]
    }

    func registerAccount(username: String, email: String, password: String) -> AnyPublisher<RegisterResponse, Error> {
        let payload: [String: String] = [
            "username": username,
            "email": email,
            "password": password
        ]
        let data = try? JSONSerialization.data(withJSONObject: payload)
        return request("auth/register/", method: "POST", body: data)
    }

    func fetchSyncState() -> AnyPublisher<SyncStateResponse, Error> {
        request("sync/")
    }

    // MARK: - Categories

    func fetchCategories() -> AnyPublisher<[Category], Error> {
        request("categories/")
    }

    func createCategory(_ category: Category) -> AnyPublisher<Category, Error> {
        do {
            return request("categories/", method: "POST", body: try jsonEncoder.encode(category))
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    func deleteCategory(id: UUID) -> AnyPublisher<Void, Error> {
        voidRequest("categories/\(id)/", method: "DELETE")
    }
}

private struct APIError: LocalizedError {
    let statusCode: Int
    let message: String

    var errorDescription: String? {
        "Server error \(statusCode): \(message)"
    }
}
