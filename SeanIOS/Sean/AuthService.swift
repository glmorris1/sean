import AuthenticationServices
import CryptoKit
import Foundation
import LocalAuthentication
import SwiftUI
import UIKit

struct AuthUser: Codable, Equatable, Identifiable {
    let id: String
    var email: String
    var isEmailVerified: Bool
    var authToken: String
    var authProvider: String? = nil
    var verificationDeliveryMode: String? = nil
    var developmentVerificationCode: String? = nil
}

enum AuthMode {
    case signIn
    case signUp
}

enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case invalidCredentials
    case emailNotVerified
    case invalidVerificationCode
    case biometricsUnavailable
    case backendUnavailable
    case emailVerificationPending
    case googleSignInUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Enter a valid email address."
        case .weakPassword:
            return "Password must be at least 8 characters."
        case .invalidCredentials:
            return "The email or password was not recognized."
        case .emailNotVerified:
            return "Verify your email before continuing."
        case .invalidVerificationCode:
            return "That verification code did not match."
        case .biometricsUnavailable:
            return "Face ID is not available on this device."
        case .backendUnavailable:
            return "GhostTrade's secure sign-in service is not configured."
        case .emailVerificationPending:
            return "Check your email, tap the Firebase verification link, then come back and tap I've Verified."
        case .googleSignInUnavailable:
            return "Google sign-in is not configured yet."
        }
    }
}

struct UserDataSnapshot: Codable {
    var watchlist: [PersistedMarketSymbol]
    var paperTradingAccount: PaperTradingAccount
    var updatedAt: Date
}

struct PersistedMarketSymbol: Codable {
    let ticker: String
    let name: String
    let exchange: String
    let assetClass: String
    let quoteCurrency: String?
    let provider: String?
    let providerSymbol: String?
    let availableTimeframes: [String]?
    let contractType: String?
    let dataAvailability: String?
    let futures: FuturesSymbol?
    let instrument: InstrumentMetadata?
    let last: Double
    let changePercent: Double
    let volume: String

    init(_ symbol: MarketSymbol) {
        ticker = symbol.ticker
        name = symbol.name
        exchange = symbol.exchange
        assetClass = symbol.assetClass
        quoteCurrency = symbol.quoteCurrency
        provider = symbol.provider
        providerSymbol = symbol.providerSymbol
        availableTimeframes = symbol.availableTimeframes
        contractType = symbol.contractType
        dataAvailability = symbol.dataAvailability
        futures = symbol.futures
        instrument = symbol.instrument
        last = symbol.last
        changePercent = symbol.changePercent
        volume = symbol.volume
    }

    var marketSymbol: MarketSymbol {
        MarketSymbol(
            ticker: ticker,
            name: name,
            exchange: exchange,
            assetClass: assetClass,
            quoteCurrency: quoteCurrency,
            provider: provider,
            providerSymbol: providerSymbol,
            availableTimeframes: availableTimeframes,
            contractType: contractType,
            dataAvailability: dataAvailability,
            futures: futures,
            instrument: instrument,
            last: last,
            changePercent: changePercent,
            volume: volume
        )
    }
}

private enum AuthBackendDefaults {
    static var bundledBackendBaseURL: String? {
        #if DEBUG
        nil
        #else
        "https://ghosttrade-auth.onrender.com"
        #endif
    }
}

private enum FirebaseConfig {
    static var webAPIKey: String? {
        if let defaultsKey = UserDefaults.standard.string(forKey: "sean.firebaseWebAPIKey"),
           !defaultsKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return defaultsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let infoKey = Bundle.main.object(forInfoDictionaryKey: "FIREBASE_WEB_API_KEY") as? String,
           !infoKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !infoKey.contains("$(") {
            return infoKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let plistURL = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
           let plist = NSDictionary(contentsOf: plistURL),
           let apiKey = plist["API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static var googleClientID: String? {
        if let defaultsKey = UserDefaults.standard.string(forKey: "sean.googleClientID"),
           !defaultsKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return defaultsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let infoKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String,
           !infoKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !infoKey.contains("$(") {
            return infoKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let plist = googleServiceInfo,
           let clientID = plist["CLIENT_ID"] as? String,
           !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static var reversedGoogleClientID: String? {
        if let defaultsKey = UserDefaults.standard.string(forKey: "sean.reversedGoogleClientID"),
           !defaultsKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return defaultsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let infoKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_REVERSED_CLIENT_ID") as? String,
           !infoKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !infoKey.contains("$(") {
            return infoKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let plist = googleServiceInfo,
           let reversedClientID = plist["REVERSED_CLIENT_ID"] as? String,
           !reversedClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return reversedClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static var googleServiceInfo: NSDictionary? {
        guard let plistURL = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") else {
            return nil
        }
        return NSDictionary(contentsOf: plistURL)
    }
}

@MainActor
@Observable
final class AuthService {
    private let sessionKey = "sean.auth.session"
    private let rememberedSessionKey = "sean.auth.rememberedSession"
    private let localUsersKey = "sean.auth.localUsers"
    private let biometricEmailKey = "sean.auth.biometricEmail"
    private let pendingFirebaseSessionKey = "sean.auth.pendingFirebaseSession"

    var currentUser: AuthUser?
    var pendingVerificationEmail: String?
    var pendingVerificationDeliveryMode: String?
    var lastDevelopmentVerificationCode: String?
    var isLoading = false
    var errorMessage: String?

    var isSignedIn: Bool {
        currentUser?.isEmailVerified == true
    }

    var canUseFaceID: Bool {
        rememberedUser != nil || UserDefaults.standard.string(forKey: biometricEmailKey) != nil
    }

    var rememberedEmail: String? {
        rememberedUser?.email ?? UserDefaults.standard.string(forKey: biometricEmailKey)
    }

    var isUsingLocalDevelopmentVerification: Bool {
        Self.allowsLocalDevelopmentAuth && lastDevelopmentVerificationCode != nil
    }

    var verificationRequiresCode: Bool {
        pendingVerificationDeliveryMode != "firebase-email-link"
    }

    var canUseGoogleSignIn: Bool {
        FirebaseConfig.webAPIKey != nil &&
            FirebaseConfig.googleClientID != nil &&
            FirebaseConfig.reversedGoogleClientID != nil
    }

    init() {
        restoreSession()
    }

    func signIn(email: String, password: String, rememberUser: Bool = false) async {
        await performAuth { [self] in
            let normalizedEmail = try normalizedEmail(email)
            try validatePassword(password)
            if FirebaseConfig.webAPIKey != nil {
                let firebaseSession = try await signInWithFirebase(email: normalizedEmail, password: password)
                if firebaseSession.emailVerified {
                    persistSession(firebaseSession.authUser, rememberUser: rememberUser)
                } else {
                    savePendingFirebaseSession(firebaseSession)
                    pendingVerificationEmail = normalizedEmail
                    pendingVerificationDeliveryMode = "firebase-email-link"
                    try? await sendFirebaseVerificationEmail(idToken: firebaseSession.idToken)
                    throw AuthError.emailNotVerified
                }
                return
            }
            do {
                let backendUser = try await authenticateWithBackend(path: "/auth/login", email: normalizedEmail, password: password)
                if backendUser.isEmailVerified {
                    persistSession(backendUser, rememberUser: rememberUser)
                } else {
                    pendingVerificationEmail = normalizedEmail
                    pendingVerificationDeliveryMode = backendUser.verificationDeliveryMode
                    throw AuthError.emailNotVerified
                }
                return
            } catch {
                guard Self.allowsLocalDevelopmentAuth else { throw error }
            }

            var users = loadLocalUsers()
            guard let local = users[normalizedEmail],
                  local.password == password else {
                throw AuthError.invalidCredentials
            }

            guard local.isEmailVerified else {
                pendingVerificationEmail = normalizedEmail
                pendingVerificationDeliveryMode = "development-code"
                throw AuthError.emailNotVerified
            }

            let user = AuthUser(id: local.id, email: normalizedEmail, isEmailVerified: true, authToken: local.authToken, authProvider: "local")
            users[normalizedEmail] = local
            saveLocalUsers(users)
            persistSession(user, rememberUser: rememberUser)
        }
    }

    func signUp(email: String, password: String) async {
        await performAuth { [self] in
            let normalizedEmail = try normalizedEmail(email)
            try validatePassword(password)
            if FirebaseConfig.webAPIKey != nil {
                let firebaseSession = try await createFirebaseAccount(email: normalizedEmail, password: password)
                savePendingFirebaseSession(firebaseSession)
                try await sendFirebaseVerificationEmail(idToken: firebaseSession.idToken)
                pendingVerificationEmail = normalizedEmail
                pendingVerificationDeliveryMode = "firebase-email-link"
                lastDevelopmentVerificationCode = nil
                return
            }
            do {
                let backendUser = try await authenticateWithBackend(path: "/auth/register", email: normalizedEmail, password: password)
                pendingVerificationEmail = normalizedEmail
                pendingVerificationDeliveryMode = backendUser.verificationDeliveryMode
                lastDevelopmentVerificationCode = backendUser.developmentVerificationCode
                if backendUser.isEmailVerified {
                    persistSession(backendUser)
                }
                return
            } catch {
                guard Self.allowsLocalDevelopmentAuth else { throw error }
            }

            let code = Self.makeVerificationCode()
            var users = loadLocalUsers()
            let existing = users[normalizedEmail]
            users[normalizedEmail] = LocalAuthRecord(
                id: existing?.id ?? UUID().uuidString,
                email: normalizedEmail,
                password: password,
                isEmailVerified: false,
                verificationCode: code,
                authToken: existing?.authToken ?? UUID().uuidString
            )
            saveLocalUsers(users)
            pendingVerificationEmail = normalizedEmail
            pendingVerificationDeliveryMode = "development-code"
            lastDevelopmentVerificationCode = code
        }
    }

    func signInWithGoogle(rememberUser: Bool = false) async {
        await performAuth { [self] in
            guard canUseGoogleSignIn else { throw AuthError.googleSignInUnavailable }
            let googleIDToken = try await requestGoogleIDToken()
            let firebaseSession = try await signInToFirebaseWithGoogle(idToken: googleIDToken)
            persistSession(firebaseSession.authUser, rememberUser: rememberUser)
        }
    }

    func resendVerification() async {
        guard let email = pendingVerificationEmail ?? currentUser?.email else { return }
        await performAuth { [self] in
            if let pendingFirebaseSession = restorePendingFirebaseSession() {
                try await sendFirebaseVerificationEmail(idToken: pendingFirebaseSession.idToken)
                pendingVerificationEmail = pendingFirebaseSession.email
                pendingVerificationDeliveryMode = "firebase-email-link"
                lastDevelopmentVerificationCode = nil
                return
            }
            do {
                let delivery = try await sendBackendVerification(email: email)
                lastDevelopmentVerificationCode = delivery.developmentVerificationCode
                pendingVerificationDeliveryMode = delivery.verificationDeliveryMode
                return
            } catch {
                guard Self.allowsLocalDevelopmentAuth else { throw error }
            }
            var users = loadLocalUsers()
            guard var record = users[email] else { return }
            let code = Self.makeVerificationCode()
            record.verificationCode = code
            users[email] = record
            saveLocalUsers(users)
            pendingVerificationDeliveryMode = "development-code"
            lastDevelopmentVerificationCode = code
        }
    }

    func verifyEmail(code: String) async {
        await performAuth { [self] in
            guard let email = pendingVerificationEmail ?? currentUser?.email else {
                throw AuthError.invalidVerificationCode
            }

            if let pendingFirebaseSession = restorePendingFirebaseSession() {
                let refreshedSession = try await lookupFirebaseAccount(idToken: pendingFirebaseSession.idToken)
                guard refreshedSession.emailVerified else {
                    throw AuthError.emailVerificationPending
                }
                persistSession(refreshedSession.authUser)
                clearPendingVerification()
                return
            }

            do {
                let backendUser = try await verifyWithBackend(email: email, code: code)
                persistSession(backendUser)
                clearPendingVerification()
                return
            } catch {
                guard Self.allowsLocalDevelopmentAuth else { throw error }
            }

            var users = loadLocalUsers()
            guard var record = users[email],
                  record.verificationCode == code.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw AuthError.invalidVerificationCode
            }

            record.isEmailVerified = true
            record.verificationCode = nil
            users[email] = record
            saveLocalUsers(users)
            persistSession(AuthUser(id: record.id, email: record.email, isEmailVerified: true, authToken: record.authToken, authProvider: "local"))
            clearPendingVerification()
        }
    }

    func unlockWithFaceID() async {
        await performAuth { [self] in
            guard let remembered = rememberedUser ?? restoreStoredSession(),
                  let email = rememberedEmail ?? UserDefaults.standard.string(forKey: biometricEmailKey) else {
                throw AuthError.biometricsUnavailable
            }
            let context = LAContext()
            var authError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
                throw AuthError.biometricsUnavailable
            }

            let unlocked = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock GhostTrade")
            guard unlocked else { throw AuthError.biometricsUnavailable }

            if remembered.isEmailVerified, remembered.email == email {
                persistSession(remembered)
            } else if let record = loadLocalUsers()[email], record.isEmailVerified {
                persistSession(AuthUser(id: record.id, email: record.email, isEmailVerified: true, authToken: record.authToken, authProvider: "local"))
            } else {
                throw AuthError.invalidCredentials
            }
        }
    }

    func enableFaceID() {
        guard let email = currentUser?.email else { return }
        UserDefaults.standard.set(email, forKey: biometricEmailKey)
        if let currentUser {
            rememberUserForBiometrics(currentUser)
        }
    }

    func signOut() {
        currentUser = nil
        clearPendingVerification()
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    private func performAuth(_ action: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func restoreSession() {
        currentUser = restoreStoredSession()
    }

    private func restoreStoredSession() -> AuthUser? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(AuthUser.self, from: data)
    }

    private func persistSession(_ user: AuthUser, rememberUser: Bool = false) {
        currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
        if rememberUser {
            rememberUserForBiometrics(user)
        }
    }

    private var rememberedUser: AuthUser? {
        guard let data = UserDefaults.standard.data(forKey: rememberedSessionKey) else { return nil }
        return try? JSONDecoder().decode(AuthUser.self, from: data)
    }

    private func rememberUserForBiometrics(_ user: AuthUser) {
        guard user.isEmailVerified,
              let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: rememberedSessionKey)
        UserDefaults.standard.set(user.email, forKey: biometricEmailKey)
    }

    func cancelPendingVerification() {
        clearPendingVerification()
        errorMessage = nil
    }

    private func clearPendingVerification() {
        pendingVerificationEmail = nil
        pendingVerificationDeliveryMode = nil
        lastDevelopmentVerificationCode = nil
        UserDefaults.standard.removeObject(forKey: pendingFirebaseSessionKey)
    }

    private func normalizedEmail(_ email: String) throws -> String {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@"), normalized.contains(".") else { throw AuthError.invalidEmail }
        return normalized
    }

    private func validatePassword(_ password: String) throws {
        guard password.count >= 8 else { throw AuthError.weakPassword }
    }

    private static func makeVerificationCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    private static func makeCodeVerifier() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    private static var allowsLocalDevelopmentAuth: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private func loadLocalUsers() -> [String: LocalAuthRecord] {
        guard let data = UserDefaults.standard.data(forKey: localUsersKey),
              let users = try? JSONDecoder().decode([String: LocalAuthRecord].self, from: data) else {
            return [:]
        }
        return users
    }

    private func saveLocalUsers(_ users: [String: LocalAuthRecord]) {
        guard let data = try? JSONEncoder().encode(users) else { return }
        UserDefaults.standard.set(data, forKey: localUsersKey)
    }

    private func createFirebaseAccount(email: String, password: String) async throws -> FirebaseAuthSession {
        let response: FirebaseAuthResponse = try await firebaseRequest(
            endpoint: "accounts:signUp",
            body: FirebaseEmailPasswordRequest(email: email, password: password, returnSecureToken: true)
        )
        return FirebaseAuthSession(response: response, emailVerified: false)
    }

    private func signInWithFirebase(email: String, password: String) async throws -> FirebaseAuthSession {
        let response: FirebaseAuthResponse = try await firebaseRequest(
            endpoint: "accounts:signInWithPassword",
            body: FirebaseEmailPasswordRequest(email: email, password: password, returnSecureToken: true)
        )
        return try await lookupFirebaseAccount(idToken: response.idToken)
    }

    private func sendFirebaseVerificationEmail(idToken: String) async throws {
        let _: FirebaseSendEmailVerificationResponse = try await firebaseRequest(
            endpoint: "accounts:sendOobCode",
            body: FirebaseSendEmailVerificationRequest(requestType: "VERIFY_EMAIL", idToken: idToken)
        )
    }

    private func lookupFirebaseAccount(idToken: String) async throws -> FirebaseAuthSession {
        let response: FirebaseLookupResponse = try await firebaseRequest(
            endpoint: "accounts:lookup",
            body: FirebaseLookupRequest(idToken: idToken)
        )
        guard let user = response.users.first else { throw AuthError.invalidCredentials }
        return FirebaseAuthSession(
            id: user.localId,
            email: user.email,
            idToken: idToken,
            emailVerified: user.emailVerified
        )
    }

    private func signInToFirebaseWithGoogle(idToken: String) async throws -> FirebaseAuthSession {
        let response: FirebaseSignInWithIdpResponse = try await firebaseRequest(
            endpoint: "accounts:signInWithIdp",
            body: FirebaseSignInWithIdpRequest(
                postBody: "id_token=\(idToken.urlFormEncoded)&providerId=google.com",
                requestUri: "https://ghosttrade.app/auth/google",
                returnIdpCredential: true,
                returnSecureToken: true
            )
        )
        return FirebaseAuthSession(
            id: response.localId,
            email: response.email,
            idToken: response.idToken,
            emailVerified: true
        )
    }

    private func requestGoogleIDToken() async throws -> String {
        guard let clientID = FirebaseConfig.googleClientID,
              let callbackScheme = FirebaseConfig.reversedGoogleClientID,
              var authComponents = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth") else {
            throw AuthError.googleSignInUnavailable
        }
        let codeVerifier = Self.makeCodeVerifier()
        let redirectURI = "\(callbackScheme):/oauth2redirect"
        authComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authURL = authComponents.url else { throw AuthError.googleSignInUnavailable }

        let callbackURL = try await WebAuthenticationCoordinator.shared.authenticate(
            url: authURL,
            callbackScheme: callbackScheme
        )
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value else {
            throw AuthError.invalidCredentials
        }
        return try await exchangeGoogleCodeForIDToken(
            code: code,
            clientID: clientID,
            redirectURI: redirectURI,
            codeVerifier: codeVerifier
        )
    }

    private func exchangeGoogleCodeForIDToken(
        code: String,
        clientID: String,
        redirectURI: String,
        codeVerifier: String
    ) async throws -> String {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw AuthError.googleSignInUnavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "client_id": clientID,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        .map { "\($0.key.urlFormEncoded)=\($0.value.urlFormEncoded)" }
        .joined(separator: "&")
        .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw AuthError.invalidCredentials
        }
        let token = try JSONDecoder().decode(GoogleOAuthTokenResponse.self, from: data)
        return token.idToken
    }

    private func firebaseRequest<RequestBody: Encodable, ResponseBody: Decodable>(
        endpoint: String,
        body: RequestBody
    ) async throws -> ResponseBody {
        guard let apiKey = FirebaseConfig.webAPIKey,
              var components = URLComponents(string: "https://identitytoolkit.googleapis.com/v1/\(endpoint)") else {
            throw AuthError.backendUnavailable
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw AuthError.backendUnavailable }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw AuthError.invalidCredentials
        }
        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }

    private func savePendingFirebaseSession(_ session: FirebaseAuthSession) {
        pendingVerificationEmail = session.email
        pendingVerificationDeliveryMode = "firebase-email-link"
        lastDevelopmentVerificationCode = nil
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: pendingFirebaseSessionKey)
        }
    }

    private func restorePendingFirebaseSession() -> FirebaseAuthSession? {
        guard let data = UserDefaults.standard.data(forKey: pendingFirebaseSessionKey) else { return nil }
        return try? JSONDecoder().decode(FirebaseAuthSession.self, from: data)
    }

    private func authenticateWithBackend(path: String, email: String, password: String) async throws -> AuthUser {
        guard var request = backendRequest(path: path) else { throw AuthError.backendUnavailable }
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(AuthCredentialsRequest(email: email, password: password))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw AuthError.invalidCredentials
        }
        return try JSONDecoder().decode(AuthUser.self, from: data)
    }

    private func sendBackendVerification(email: String) async throws -> VerificationDeliveryResponse {
        guard var request = backendRequest(path: "/auth/verification/resend") else { throw AuthError.backendUnavailable }
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(AuthEmailRequest(email: email))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw AuthError.invalidCredentials
        }
        return try JSONDecoder().decode(VerificationDeliveryResponse.self, from: data)
    }

    private func verifyWithBackend(email: String, code: String) async throws -> AuthUser {
        guard var request = backendRequest(path: "/auth/verify-email") else { throw AuthError.invalidVerificationCode }
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(AuthVerificationRequest(email: email, code: code))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw AuthError.invalidVerificationCode
        }
        return try JSONDecoder().decode(AuthUser.self, from: data)
    }

    private func backendRequest(path: String) -> URLRequest? {
        guard var components = backendURLComponents(for: "sean.authBackendBaseURL") else {
            return nil
        }
        components.path = path
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func backendURLComponents(for userDefaultsKey: String) -> URLComponents? {
        let rawBaseURL = UserDefaults.standard.string(forKey: userDefaultsKey) ??
            (Bundle.main.object(forInfoDictionaryKey: "SEAN_API_BASE_URL") as? String) ??
            AuthBackendDefaults.bundledBackendBaseURL
        guard let rawBaseURL,
              !rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var components = URLComponents(string: rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased() else {
            return nil
        }
        #if DEBUG
        guard scheme == "https" || scheme == "http" else { return nil }
        #else
        guard scheme == "https" else { return nil }
        #endif
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components
    }
}

private struct LocalAuthRecord: Codable {
    var id: String
    var email: String
    var password: String
    var isEmailVerified: Bool
    var verificationCode: String?
    var authToken: String
}

private struct AuthCredentialsRequest: Encodable {
    let email: String
    let password: String
}

private struct AuthEmailRequest: Encodable {
    let email: String
}

private struct AuthVerificationRequest: Encodable {
    let email: String
    let code: String
}

private struct VerificationDeliveryResponse: Decodable {
    let verificationDeliveryMode: String?
    let developmentVerificationCode: String?
}

private struct FirebaseEmailPasswordRequest: Encodable {
    let email: String
    let password: String
    let returnSecureToken: Bool
}

private struct FirebaseSendEmailVerificationRequest: Encodable {
    let requestType: String
    let idToken: String
}

private struct FirebaseLookupRequest: Encodable {
    let idToken: String
}

private struct FirebaseAuthResponse: Decodable {
    let localId: String
    let email: String
    let idToken: String
}

private struct FirebaseSendEmailVerificationResponse: Decodable {
    let email: String?
}

private struct FirebaseLookupResponse: Decodable {
    let users: [FirebaseLookupUser]
}

private struct FirebaseLookupUser: Decodable {
    let localId: String
    let email: String
    let emailVerified: Bool
}

private struct FirebaseSignInWithIdpRequest: Encodable {
    let postBody: String
    let requestUri: String
    let returnIdpCredential: Bool
    let returnSecureToken: Bool
}

private struct FirebaseSignInWithIdpResponse: Decodable {
    let localId: String
    let email: String
    let idToken: String
}

private struct GoogleOAuthTokenResponse: Decodable {
    let idToken: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
    }
}

private struct FirebaseAuthSession: Codable {
    let id: String
    let email: String
    let idToken: String
    let emailVerified: Bool

    init(id: String, email: String, idToken: String, emailVerified: Bool) {
        self.id = id
        self.email = email
        self.idToken = idToken
        self.emailVerified = emailVerified
    }

    init(response: FirebaseAuthResponse, emailVerified: Bool) {
        id = response.localId
        email = response.email
        idToken = response.idToken
        self.emailVerified = emailVerified
    }

    var authUser: AuthUser {
        AuthUser(
            id: id,
            email: email,
            isEmailVerified: emailVerified,
            authToken: idToken,
            authProvider: "firebase",
            verificationDeliveryMode: "firebase-email-link"
        )
    }
}

private final class WebAuthenticationCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthenticationCoordinator()
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? AuthError.invalidCredentials)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: AuthError.googleSignInUnavailable)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var urlFormEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

enum UserDataSyncService {
    static func fetchSnapshot(for user: AuthUser) async throws -> UserDataSnapshot? {
        guard var request = syncRequest(path: "/user-data", user: user) else { return nil }
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return nil }
        guard httpResponse.statusCode != 404 else { return nil }
        guard 200..<300 ~= httpResponse.statusCode else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UserDataSnapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: UserDataSnapshot, for user: AuthUser) async {
        guard var request = syncRequest(path: "/user-data", user: user) else { return }
        request.httpMethod = "PUT"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try? encoder.encode(snapshot)
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func syncRequest(path: String, user: AuthUser) -> URLRequest? {
        let baseURL = UserDefaults.standard.string(forKey: "sean.syncBackendBaseURL") ??
            UserDefaults.standard.string(forKey: "sean.authBackendBaseURL") ??
            (Bundle.main.object(forInfoDictionaryKey: "SEAN_API_BASE_URL") as? String) ??
            AuthBackendDefaults.bundledBackendBaseURL
        guard let rawBaseURL = baseURL,
              !rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var components = URLComponents(string: rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        #if !DEBUG
        guard components.scheme?.lowercased() == "https" else { return nil }
        #endif
        components.path = path
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(user.authToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}
