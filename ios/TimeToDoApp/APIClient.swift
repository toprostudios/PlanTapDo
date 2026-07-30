// APIClient.swift
import Foundation
import Combine

final class APIClient {
    static let shared = APIClient()
    private let baseURL = URL(string: "http://localhost:8000/api")!
    private var token: String?

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

    private init() {}

    // MARK: - Auth

    func setAuthToken(_ token: String) {
        self.token = token
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
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
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
        let data = try? jsonEncoder.encode(todo)
        return request("todos/", method: "POST", body: data)
    }

    func updateTodo(_ todo: TodoEntry) -> AnyPublisher<TodoEntry, Error> {
        let data = try? jsonEncoder.encode(todo)
        return request("todos/\(todo.id)/", method: "PUT", body: data)
    }

    func deleteTodo(id: UUID) -> AnyPublisher<Void, Error> {
        voidRequest("todos/\(id)/", method: "DELETE")
    }

    // MARK: - Categories

    func fetchCategories() -> AnyPublisher<[Category], Error> {
        request("categories/")
    }
}
