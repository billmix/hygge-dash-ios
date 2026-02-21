import Foundation
import UIKit
import AuthenticationServices
import Security
import Combine

@MainActor
class SonosAuthService: NSObject, ObservableObject {
    @Published var isAuthenticated = false

    private let authURL = "https://api.sonos.com/login/v3/oauth"
    private let tokenURL = "https://api.sonos.com/login/v3/oauth/access"
    private let keychainServiceName = "com.hyggedash.sonos"

    private var clientId: String {
        Bundle.main.infoDictionary?["SonosClientID"] as? String ?? ""
    }

    private var clientSecret: String {
        Bundle.main.infoDictionary?["SonosClientSecret"] as? String ?? ""
    }

    private var redirectURI: String {
        Bundle.main.infoDictionary?["SonosRedirectURI"] as? String ?? ""
    }

    private var accessTokenExpiresAt: Date?

    override init() {
        super.init()
        isAuthenticated = loadToken(for: "access_token") != nil
    }

    // MARK: - Public API

    func authenticate() {
        guard var components = URLComponents(string: authURL) else { return }

        let state = UUID().uuidString
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "playback-control-all"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
        ]

        guard let url = components.url else { return }

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "hyggehousehold"
        ) { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    print("Auth error: \(error.localizedDescription)")
                    return
                }

                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                      let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
                      returnedState == state else {
                    print("Auth failed: invalid callback")
                    return
                }

                do {
                    try await self.exchangeCodeForTokens(code: code)
                    self.isAuthenticated = true
                } catch {
                    print("Token exchange failed: \(error.localizedDescription)")
                }
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    func refreshTokenIfNeeded() async throws -> String {
        // Return current token if not expired
        if let expiresAt = accessTokenExpiresAt, Date() < expiresAt,
           let token = loadToken(for: "access_token") {
            return token
        }

        // Try to refresh
        guard let refreshToken = loadToken(for: "refresh_token") else {
            isAuthenticated = false
            throw AuthError.noRefreshToken
        }

        let credentials = "\(clientId):\(clientSecret)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw AuthError.encodingError
        }
        let base64Credentials = credentialsData.base64EncodedString()

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            isAuthenticated = false
            throw AuthError.refreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        saveToken(tokenResponse.accessToken, for: "access_token")
        saveToken(tokenResponse.refreshToken, for: "refresh_token")
        accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))
        isAuthenticated = true

        return tokenResponse.accessToken
    }

    func logout() {
        deleteToken(for: "access_token")
        deleteToken(for: "refresh_token")
        accessTokenExpiresAt = nil
        isAuthenticated = false
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String) async throws {
        let credentials = "\(clientId):\(clientSecret)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw AuthError.encodingError
        }
        let base64Credentials = credentialsData.base64EncodedString()

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURI)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        saveToken(tokenResponse.accessToken, for: "access_token")
        saveToken(tokenResponse.refreshToken, for: "refresh_token")
        accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))
    }

    // MARK: - Keychain

    private func saveToken(_ token: String, for account: String) {
        let data = token.data(using: .utf8)!

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadToken(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteToken(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Types

    enum AuthError: LocalizedError {
        case noRefreshToken
        case encodingError
        case refreshFailed
        case tokenExchangeFailed

        var errorDescription: String? {
            switch self {
            case .noRefreshToken: return "No refresh token available. Please log in again."
            case .encodingError: return "Failed to encode credentials."
            case .refreshFailed: return "Failed to refresh access token."
            case .tokenExchangeFailed: return "Failed to exchange authorization code for tokens."
            }
        }
    }

    private struct TokenResponse: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let tokenType: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
        }
    }
}

extension SonosAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}
