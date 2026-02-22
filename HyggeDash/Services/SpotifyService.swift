import Foundation
import AuthenticationServices
import UIKit
import CryptoKit

/// Handles Spotify OAuth (PKCE) and Web API playback via Spotify Connect
@MainActor
class SpotifyService: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var authError: String?
    @Published var availableDevices: [SpotifyDevice] = []

    private let authURL = "https://accounts.spotify.com/authorize"
    private let tokenURL = "https://accounts.spotify.com/api/token"
    private let apiBase = "https://api.spotify.com/v1"
    private let keychainService = "com.hyggedash.spotify"

    // PKCE
    private var codeVerifier: String?
    private var authSession: ASWebAuthenticationSession?
    private var accessTokenExpiresAt: Date?

    private var clientId: String {
        Bundle.main.infoDictionary?["SpotifyClientID"] as? String ?? ""
    }

    // Redirect through our Firebase site (same domain as Sonos)
    private let redirectURI = "https://hyggehousehold.web.app/spotify-callback"

    // Scopes needed for playback control
    private let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "streaming",
        "app-remote-control",
    ].joined(separator: " ")

    override init() {
        super.init()
        isAuthenticated = loadToken(for: "access_token") != nil
    }

    // MARK: - OAuth (PKCE)

    func authenticate() {
        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)
        let state = UUID().uuidString

        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]

        guard let url = components.url else { return }

        print("🎵 [SPOTIFY AUTH] Starting OAuth PKCE flow")
        print("🎵 [SPOTIFY AUTH] Client ID: \(clientId.prefix(8))...")
        print("🎵 [SPOTIFY AUTH] Redirect: \(redirectURI)")

        let completion: (URL?, Error?) -> Void = { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.authSession = nil

                if let error {
                    print("🎵 [SPOTIFY AUTH] ❌ Error: \(error.localizedDescription)")
                    self.authError = error.localizedDescription
                    return
                }

                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    self.authError = "No authorization code received"
                    return
                }

                print("🎵 [SPOTIFY AUTH] ✅ Got code: \(code.prefix(8))...")

                do {
                    try await self.exchangeCode(code)
                    self.isAuthenticated = true
                    print("🎵 [SPOTIFY AUTH] ✅ Authenticated!")
                    await self.fetchDevices()
                } catch {
                    print("🎵 [SPOTIFY AUTH] ❌ Token exchange failed: \(error)")
                    self.authError = "Token exchange failed: \(error.localizedDescription)"
                }
            }
        }

        if #available(iOS 17.4, *) {
            authSession = ASWebAuthenticationSession(
                url: url,
                callback: .https(host: "hyggehousehold.web.app", path: "/spotify-callback"),
                completionHandler: completion
            )
        } else {
            authSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "hyggehousehold",
                completionHandler: completion
            )
        }

        authSession!.presentationContextProvider = self
        authSession!.prefersEphemeralWebBrowserSession = false
        authSession!.start()
    }

    // MARK: - Token Exchange (PKCE — no client secret)

    private func exchangeCode(_ code: String) async throws {
        guard let verifier = codeVerifier else { throw SpotifyError.noCodeVerifier }

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("🎵 [SPOTIFY TOKEN] Status: \(status)")

        guard status == 200 else {
            print("🎵 [SPOTIFY TOKEN] ❌ Body: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw SpotifyError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        saveToken(tokenResponse.accessToken, for: "access_token")
        if let refresh = tokenResponse.refreshToken {
            saveToken(refresh, for: "refresh_token")
        }
        accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))
        codeVerifier = nil
    }

    func refreshTokenIfNeeded() async throws -> String {
        if let expiresAt = accessTokenExpiresAt, Date() < expiresAt,
           let token = loadToken(for: "access_token") {
            return token
        }

        guard let refreshToken = loadToken(for: "refresh_token") else {
            isAuthenticated = false
            throw SpotifyError.noRefreshToken
        }

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientId),
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            isAuthenticated = false
            throw SpotifyError.refreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        saveToken(tokenResponse.accessToken, for: "access_token")
        if let refresh = tokenResponse.refreshToken {
            saveToken(refresh, for: "refresh_token")
        }
        accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))
        isAuthenticated = true
        return tokenResponse.accessToken
    }

    func logout() {
        deleteToken(for: "access_token")
        deleteToken(for: "refresh_token")
        accessTokenExpiresAt = nil
        isAuthenticated = false
        availableDevices = []
    }

    // MARK: - Spotify Web API

    private func apiRequest(url: URL, method: String = "GET", body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        let token = try await refreshTokenIfNeeded()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyError.invalidResponse
        }
        return (data, http)
    }

    // MARK: - Devices (Spotify Connect)

    func fetchDevices() async {
        do {
            let (data, response) = try await apiRequest(url: URL(string: "\(apiBase)/me/player/devices")!)
            print("🎵 [SPOTIFY] Devices response: \(response.statusCode)")

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let devices = json["devices"] as? [[String: Any]] else {
                print("🎵 [SPOTIFY] No devices found")
                return
            }

            availableDevices = devices.compactMap { device in
                guard let id = device["id"] as? String,
                      let name = device["name"] as? String,
                      let type = device["type"] as? String else { return nil }
                let isActive = device["is_active"] as? Bool ?? false
                print("🎵 [SPOTIFY] Device: \(name) (\(type)) active=\(isActive) id=\(id)")
                return SpotifyDevice(id: id, name: name, type: type, isActive: isActive)
            }
        } catch {
            print("🎵 [SPOTIFY] ❌ Fetch devices error: \(error)")
        }
    }

    // MARK: - Playback Control

    /// Play a Spotify URI on a specific device (or active device)
    func play(uri: String, deviceId: String? = nil) async {
        do {
            var url = URLComponents(string: "\(apiBase)/me/player/play")!
            if let deviceId {
                url.queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
            }

            // Determine if this is a track or a context (album/playlist)
            let body: [String: Any]
            if uri.contains(":track:") {
                body = ["uris": [uri]]
            } else {
                body = ["context_uri": uri]
            }

            print("🎵 [SPOTIFY] Playing \(uri) on device \(deviceId ?? "active")")
            let (data, response) = try await apiRequest(url: url.url!, method: "PUT", body: body)
            print("🎵 [SPOTIFY] Play response: \(response.statusCode)")
            if response.statusCode >= 400 {
                print("🎵 [SPOTIFY] Play error: \(String(data: data, encoding: .utf8) ?? "nil")")
            }
        } catch {
            print("🎵 [SPOTIFY] ❌ Play error: \(error)")
        }
    }

    func pause() async {
        do {
            let (_, response) = try await apiRequest(
                url: URL(string: "\(apiBase)/me/player/pause")!,
                method: "PUT"
            )
            print("🎵 [SPOTIFY] Pause: \(response.statusCode)")
        } catch {
            print("🎵 [SPOTIFY] ❌ Pause error: \(error)")
        }
    }

    func skipNext() async {
        do {
            let (data, response) = try await apiRequest(
                url: URL(string: "\(apiBase)/me/player/next")!,
                method: "POST"
            )
            print("🎵 [SPOTIFY] Skip next: \(response.statusCode)")
            if response.statusCode >= 400 {
                print("🎵 [SPOTIFY] Skip error: \(String(data: data, encoding: .utf8) ?? "nil")")
            }
        } catch {
            print("🎵 [SPOTIFY] ❌ Skip error: \(error)")
        }
    }

    func skipPrevious() async {
        do {
            let (_, response) = try await apiRequest(
                url: URL(string: "\(apiBase)/me/player/previous")!,
                method: "POST"
            )
            print("🎵 [SPOTIFY] Skip prev: \(response.statusCode)")
        } catch {
            print("🎵 [SPOTIFY] ❌ Skip prev error: \(error)")
        }
    }

    /// Transfer playback to a device
    func transferPlayback(to deviceId: String) async {
        do {
            let (_, response) = try await apiRequest(
                url: URL(string: "\(apiBase)/me/player")!,
                method: "PUT",
                body: ["device_ids": [deviceId], "play": true]
            )
            print("🎵 [SPOTIFY] Transfer to \(deviceId): \(response.statusCode)")
        } catch {
            print("🎵 [SPOTIFY] ❌ Transfer error: \(error)")
        }
    }

    /// Find a Sonos device by matching speaker name
    func findSonosDevice(named speakerName: String) -> SpotifyDevice? {
        // Sonos speakers appear as "Speaker" type in Spotify Connect
        return availableDevices.first { device in
            device.name.localizedCaseInsensitiveContains(speakerName) ||
            speakerName.localizedCaseInsensitiveContains(device.name)
        }
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Keychain

    private func saveToken(_ token: String, for account: String) {
        let data = token.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadToken(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteToken(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Types

    enum SpotifyError: LocalizedError {
        case noCodeVerifier, noRefreshToken, tokenExchangeFailed, refreshFailed, invalidResponse

        var errorDescription: String? {
            switch self {
            case .noCodeVerifier: return "Missing PKCE code verifier"
            case .noRefreshToken: return "No refresh token. Please log in again."
            case .tokenExchangeFailed: return "Failed to exchange authorization code"
            case .refreshFailed: return "Failed to refresh Spotify token"
            case .invalidResponse: return "Invalid response from Spotify"
            }
        }
    }
}

struct SpotifyDevice: Identifiable {
    let id: String
    let name: String
    let type: String
    let isActive: Bool
}

private struct SpotifyTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

extension SpotifyService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}
