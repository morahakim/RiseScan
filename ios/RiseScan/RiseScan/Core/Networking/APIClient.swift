//
//  APIClient.swift
//  RiseScan
//
//  Created by mora hakim on 14/11/26.
//


import Foundation

enum APIError: Error {
    case invalidResponse
    case serverError(Int)
}

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300

        session = URLSession(configuration: configuration)
    }

    func get<T: Decodable>(_ endpoint: String) async throws -> T {
        let url = APIConfig.baseURL.appending(path: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
    
    
    func post<Request: Encodable, Response: Decodable>(_ endpoint: String, body: Request) async throws -> Response {
        let url = APIConfig.baseURL.appending(path: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

}

