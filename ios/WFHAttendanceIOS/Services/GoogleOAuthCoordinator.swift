import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

final class GoogleOAuthCoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func signIn() async throws -> String {
        let clientID = Bundle.main.googleIOSClientID
        guard !clientID.isEmpty else {
            throw AppError.message("Google sign-in is not configured yet. Add a Google iOS OAuth client ID to GOOGLE_IOS_CLIENT_ID in Xcode.")
        }
        guard let callbackScheme = Bundle.main.googleIOSCallbackScheme ?? clientID.googleCallbackScheme else {
            throw AppError.message("Google sign-in needs an iOS OAuth callback scheme configured.")
        }

        let redirectURI = "\(callbackScheme):/oauth2redirect"
        let codeVerifier = Self.makeCodeVerifier()
        let codeChallenge = Self.codeChallenge(for: codeVerifier)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let url = components.url else {
            throw AppError.message("Could not start Google sign-in.")
        }

        let code = try await requestAuthorizationCode(url: url, callbackScheme: callbackScheme)
        return try await exchangeCodeForIDToken(
            code: code,
            clientID: clientID,
            redirectURI: redirectURI,
            codeVerifier: codeVerifier
        )
    }

    private func requestAuthorizationCode(url: URL, callbackScheme: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                self?.session = nil
                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: AppError.message("Google sign-in was cancelled."))
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL,
                      let code = callbackURL.queryParameters["code"],
                      !code.isEmpty else {
                    if let message = callbackURL?.queryParameters["error_description"] ?? callbackURL?.queryParameters["error"] {
                        continuation.resume(throwing: AppError.message(message))
                    } else {
                        continuation.resume(throwing: AppError.message("Google did not return an authorization code. Try again."))
                    }
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: AppError.message("Could not start Google sign-in."))
            }
        }
    }

    private func exchangeCodeForIDToken(code: String, clientID: String, redirectURI: String, codeVerifier: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 28
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let error = try? JSONDecoder().decode(GoogleTokenError.self, from: data) {
                throw AppError.message(error.errorDescription ?? error.error)
            }
            throw AppError.message("Google token exchange failed.")
        }

        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        guard !tokenResponse.idToken.isEmpty else {
            throw AppError.message("Google did not return a sign-in credential. Try again.")
        }
        return tokenResponse.idToken
    }

    private static func makeCodeVerifier() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<64).compactMap { _ in alphabet.randomElement() })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
