import Foundation
import UIKit
import AuthenticationServices
import Security
import Combine

@MainActor
class SonosAuthService: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var authError: String?

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
        // Sonos requires an HTTPS redirect URI. The page at this URL relays
        // the auth code to our custom URL scheme (hyggehousehold://callback)
        // which ASWebAuthenticationSession intercepts.
        return "https://hyggehousehold.web.app/callback"
    }

    private var accessTokenExpiresAt: Date?
    private var authSession: ASWebAuthenticationSession?

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

        print("🎵 [AUTH] Starting OAuth flow")
        print("🎵 [AUTH] Auth URL: \(url.absoluteString)")
        print("🎵 [AUTH] clientId: \(clientId.prefix(8))..., redirectURI: \(redirectURI)")
        print("🎵 [AUTH] State: \(state)")

        // Completion handler shared by both code paths
        let completionHandler: (URL?, Error?) -> Void = { [weak self] callbackURL, error in
            print("🎵 [AUTH] ✅ Callback received!")
            print("🎵 [AUTH] callbackURL: \(callbackURL?.absoluteString ?? "nil")")
            print("🎵 [AUTH] error: \(error?.localizedDescription ?? "nil")")

            Task { @MainActor [weak self] in
                guard let self else {
                    print("🎵 [AUTH] ⚠️ Self was deallocated before callback processed")
                    return
                }

                // Clear the session reference
                self.authSession = nil

                if let error {
                    print("🎵 [AUTH] ❌ Auth error: \(error.localizedDescription)")
                    print("🎵 [AUTH] ❌ Error code: \((error as NSError).code), domain: \((error as NSError).domain)")
                    self.authError = error.localizedDescription
                    return
                }

                guard let callbackURL else {
                    print("🎵 [AUTH] ❌ No callback URL and no error")
                    self.authError = "No callback URL received"
                    return
                }

                guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
                    print("🎵 [AUTH] ❌ Could not parse callback URL: \(callbackURL)")
                    self.authError = "Invalid callback URL"
                    return
                }

                print("🎵 [AUTH] Callback query items: \(components.queryItems?.map { "\($0.name)=\($0.value ?? "nil")" } ?? [])")

                guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    print("🎵 [AUTH] ❌ No 'code' in callback URL")
                    self.authError = "No authorization code received"
                    return
                }

                guard let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
                      returnedState == state else {
                    print("🎵 [AUTH] ❌ State mismatch! Expected: \(state)")
                    self.authError = "State mismatch in callback"
                    return
                }

                print("🎵 [AUTH] ✅ Got auth code: \(code.prefix(8))... State verified.")
                print("🎵 [AUTH] Exchanging code for tokens...")

                do {
                    try await self.exchangeCodeForTokens(code: code)
                    print("🎵 [AUTH] ✅ Token exchange succeeded! isAuthenticated = true")
                    self.isAuthenticated = true
                } catch {
                    print("🎵 [AUTH] ❌ Token exchange failed: \(error)")
                    self.authError = "Token exchange failed: \(error.localizedDescription)"
                }
            }
        }

        // Use HTTPS callback (intercepts the redirect URL directly, no JS relay needed)
        // Falls back to custom scheme for older iOS versions
        if #available(iOS 17.4, *) {
            print("🎵 [AUTH] Using HTTPS callback: hyggehousehold.web.app/callback")
            authSession = ASWebAuthenticationSession(
                url: url,
                callback: .https(host: "hyggehousehold.web.app", path: "/callback"),
                completionHandler: completionHandler
            )
        } else {
            print("🎵 [AUTH] Using custom scheme callback: hyggehousehold")
            authSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "hyggehousehold",
                completionHandler: completionHandler
            )
        }

        authSession!.presentationContextProvider = self
        authSession!.prefersEphemeralWebBrowserSession = false

        let started = authSession!.start()
        print("🎵 [AUTH] Session started: \(started)")
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
        print("🎵 [TOKEN] Starting token exchange...")
        print("🎵 [TOKEN] Token URL: \(tokenURL)")
        print("🎵 [TOKEN] Redirect URI: \(redirectURI)")

        let credentials = "\(clientId):\(clientSecret)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            print("🎵 [TOKEN] ❌ Failed to encode credentials")
            throw AuthError.encodingError
        }
        let base64Credentials = credentialsData.base64EncodedString()

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        let bodyString = bodyComponents.percentEncodedQuery ?? ""
        request.httpBody = bodyString.data(using: .utf8)
        print("🎵 [TOKEN] Request body: \(bodyString.replacingOccurrences(of: code, with: "\(code.prefix(8))..."))")

        print("🎵 [TOKEN] Sending token exchange request...")
        let (data, response) = try await URLSession.shared.data(for: request)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let responseBody = String(data: data, encoding: .utf8) ?? "nil"
        print("🎵 [TOKEN] Response status: \(statusCode)")
        print("🎵 [TOKEN] Response body: \(responseBody.prefix(500))")

        guard statusCode == 200 else {
            print("🎵 [TOKEN] ❌ Non-200 status code: \(statusCode)")
            throw AuthError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        print("🎵 [TOKEN] ✅ Decoded token response. ExpiresIn: \(tokenResponse.expiresIn)s")
        saveToken(tokenResponse.accessToken, for: "access_token")
        saveToken(tokenResponse.refreshToken, for: "refresh_token")
        accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))
        print("🎵 [TOKEN] ✅ Tokens saved to keychain")
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
