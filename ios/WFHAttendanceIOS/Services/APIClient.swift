import Foundation

private let apiBase = URL(string: "https://wfh-one.vercel.app")!

final class APIClient {
    var token: String?

    func request<T: Decodable>(path: String, method: String) async throws -> T {
        try await request(path: path, method: method, body: Optional<String>.none)
    }

    func request<T: Decodable, Body: Encodable>(path: String, method: String, body: Body?) async throws -> T {
        var request = URLRequest(url: apiBase.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 28
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                throw AppError.message(apiError.error)
            }
            throw AppError.message("Server returned \(status).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct APIError: Decodable {
    let error: String
}

enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}
