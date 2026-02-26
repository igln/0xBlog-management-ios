import SwiftUI

@main
struct BlogAppApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var isConfigured: Bool = false
    @Published var serverHost: String = ""
    @Published var serverPort: Int = 8081
    @Published var apiKey: String = ""
    
    @Published var posts: [BlogPost] = []
    @Published var pendingComments: [BlogComment] = []
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let keychainService = KeychainService()
    
    init() {
        loadConfiguration()
    }
    
    func loadConfiguration() {
        serverHost = UserDefaults.standard.string(forKey: "serverHost") ?? ""
        serverPort = UserDefaults.standard.integer(forKey: "serverPort")
        if serverPort == 0 { serverPort = 8081 }
        
        if let key = keychainService.getApiKey() {
            apiKey = key
        }
        
        isConfigured = !serverHost.isEmpty && !apiKey.isEmpty
        
        if isConfigured {
            BlogAPIClient.shared.configure(host: serverHost, port: serverPort, apiKey: apiKey)
        }
    }
    
    func saveConfiguration(host: String, port: Int, apiKey: String) {
        self.serverHost = host
        self.serverPort = port
        self.apiKey = apiKey
        
        UserDefaults.standard.set(host, forKey: "serverHost")
        UserDefaults.standard.set(port, forKey: "serverPort")
        keychainService.saveApiKey(apiKey)
        
        BlogAPIClient.shared.configure(host: host, port: port, apiKey: apiKey)
        
        isConfigured = !host.isEmpty && !apiKey.isEmpty
    }
    
    func clearConfiguration() {
        serverHost = ""
        serverPort = 8081
        apiKey = ""
        
        UserDefaults.standard.removeObject(forKey: "serverHost")
        UserDefaults.standard.removeObject(forKey: "serverPort")
        keychainService.deleteApiKey()
        
        isConfigured = false
    }
}

// MARK: - Models

struct BlogPost: Codable, Identifiable {
    var id: Int64 = 0
    var content: String = ""
    var createdAt: Int64 = 0
    var published: Bool = false
    var commentCount: Int = 0
}

struct BlogComment: Codable, Identifiable {
    var id: Int64 = 0
    var postId: Int64 = 0
    var authorName: String = ""
    var content: String = ""
    var createdAt: Int64 = 0
    var approved: Bool = false
}

// MARK: - API Client

class BlogAPIClient {
    private var baseURL: String = ""
    private var apiKey: String = ""
    
    static let shared = BlogAPIClient()
    
    private init() {}
    
    func configure(host: String, port: Int, apiKey: String) {
        self.baseURL = "http://\(host):\(port)"
        self.apiKey = apiKey
    }
    
    var isConfigured: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty
    }
    
    private func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        requiresAuth: Bool = false
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if requiresAuth {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
    
    func getPosts(page: Int = 1, limit: Int = 50) async throws -> PostsResponse {
        try await request(endpoint: "/api/posts?page=\(page)&limit=\(limit)")
    }
    
    func getPost(id: Int64) async throws -> BlogPost {
        try await request(endpoint: "/api/posts/\(id)")
    }
    
    func createPost(content: String) async throws -> BlogPost {
        let body = try JSONEncoder().encode(["content": content])
        return try await request(endpoint: "/api/posts", method: "POST", body: body, requiresAuth: true)
    }
    
    func deletePost(id: Int64) async throws {
        let _: EmptyResponse = try await request(endpoint: "/api/posts/\(id)", method: "DELETE", requiresAuth: true)
    }
    
    func getComments(postId: Int64) async throws -> CommentsResponse {
        try await request(endpoint: "/api/comments/post/\(postId)")
    }
    
    func getPendingComments() async throws -> CommentsResponse {
        try await request(endpoint: "/api/comments/pending", requiresAuth: true)
    }
    
    func moderateComment(id: Int64, approve: Bool) async throws -> BlogComment {
        let body = try JSONEncoder().encode(["approve": approve])
        return try await request(endpoint: "/api/comments/\(id)/moderate", method: "PUT", body: body, requiresAuth: true)
    }
    
    func deleteComment(id: Int64) async throws {
        let _: EmptyResponse = try await request(endpoint: "/api/comments/\(id)", method: "DELETE", requiresAuth: true)
    }
}

struct PostsResponse: Codable {
    let posts: [BlogPost]
    let totalCount: Int
}

struct CommentsResponse: Codable {
    let comments: [BlogComment]
}

struct EmptyResponse: Codable {}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int, message: String)
    case notConfigured
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .notConfigured:
            return "API client not configured"
        }
    }
}

// MARK: - Keychain Service

class KeychainService {
    private let service = "com.blog.BlogApp"
    private let apiKeyAccount = "apiKey"
    
    func saveApiKey(_ apiKey: String) {
        guard let data = apiKey.data(using: .utf8) else { return }
        
        deleteApiKey()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func getApiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return apiKey
    }
    
    func deleteApiKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
