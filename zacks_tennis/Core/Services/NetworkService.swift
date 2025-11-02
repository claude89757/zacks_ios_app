//
//  NetworkService.swift
//  zacks_tennis
//
//  网络服务 - 处理 API 请求和数据同步
//

import Foundation

/// 网络服务
@MainActor
@Observable
class NetworkService {
    static let shared = NetworkService()

    var isLoading: Bool = false
    var lastError: Error?

    private let session: URLSession
    private let baseURL = "https://api.zackstennis.com" // 替换为实际的 API 地址

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - 网球场相关 API

    /// 获取城市的网球场列表
    func fetchCourts(city: String) async throws -> [CourtData] {
        let endpoint = "/api/v1/courts"
        var components = URLComponents(string: baseURL + endpoint)
        components?.queryItems = [URLQueryItem(name: "city", value: city)]

        guard let url = components?.url else {
            throw NetworkError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(CourtsResponse.self, from: data)

        return result.courts
    }

    /// 检查球场可用性
    func checkCourtAvailability(courtID: String, date: Date, timeSlot: String) async throws -> Bool {
        // 这里是示例实现，实际需要根据真实 API 调整
        let endpoint = "/api/v1/courts/\(courtID)/availability"
        var components = URLComponents(string: baseURL + endpoint)

        let dateFormatter = ISO8601DateFormatter()
        components?.queryItems = [
            URLQueryItem(name: "date", value: dateFormatter.string(from: date)),
            URLQueryItem(name: "time_slot", value: timeSlot)
        ]

        guard let url = components?.url else {
            throw NetworkError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError
        }

        let result = try JSONDecoder().decode(AvailabilityResponse.self, from: data)
        return result.isAvailable
    }

    // MARK: - AI 聊天相关 API (OpenAI)

    /// 发送聊天消息到 OpenAI
    func sendChatMessage(messages: [APIChatMessage], apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "max_tokens": 1000,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError
        }

        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return result.choices.first?.message.content ?? ""
    }

    // MARK: - 用户相关 API

    /// 同步用户数据到服务器（可选功能）
    func syncUserData(_ user: User) async throws {
        // 预留接口，后续实现
        print("同步用户数据: \(user.username)")
    }

    // MARK: - 辅助方法

    /// 通用 GET 请求
    func get<T: Decodable>(endpoint: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        var components = URLComponents(string: baseURL + endpoint)
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw NetworkError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    /// 通用 POST 请求
    func post<T: Encodable, R: Decodable>(endpoint: String, body: T) async throws -> R {
        guard let url = URL(string: baseURL + endpoint) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(R.self, from: data)
    }
}

// MARK: - 数据模型

struct CourtData: Codable {
    let id: String
    let name: String
    let city: String
    let address: String
    let courtCount: Int
    let surfaceType: String
    let priceRange: String
}

struct CourtsResponse: Codable {
    let courts: [CourtData]
    let total: Int
}

struct AvailabilityResponse: Codable {
    let isAvailable: Bool
    let timeSlot: String
}

struct APIChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatCompletionResponse: Codable {
    let choices: [ChatChoice]

    struct ChatChoice: Codable {
        let message: APIChatMessage
    }
}

// MARK: - 错误类型
enum NetworkError: LocalizedError {
    case invalidURL
    case serverError
    case decodingError
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .serverError:
            return "服务器错误"
        case .decodingError:
            return "数据解析失败"
        case .noData:
            return "没有返回数据"
        }
    }
}
