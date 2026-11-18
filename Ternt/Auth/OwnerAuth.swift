import AuthenticationServices
import Foundation
import GoogleSignIn
import Supabase
import UIKit

enum PortraitStore {
    static func upload(_ image: UIImage, id: String) async -> String? {
        guard let user = try? await TernedBackend.client.auth.session.user else { return nil }
        let maxSide: CGFloat = 640
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 0 ? min(1, maxSide / longest) : 1
        let size = CGSize(width: max(image.size.width * scale, 1), height: max(image.size.height * scale, 1))
        let data = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.86) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        let path = "\(user.id.uuidString.lowercased())/\(id).jpg"
        do {
            try await TernedBackend.client.storage.from("avatars").upload(
                path,
                data: data,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
            let nonce = String(Int(Date().timeIntervalSince1970))
            return try TernedBackend.client.storage.from("avatars").getPublicURL(path: path, cacheNonce: nonce).absoluteString
        } catch {
            return nil
        }
    }
}

enum TernedBackend {
    static let url = URL(string: "https://myuklwcvllcdkfhancoo.supabase.co")!
    static let publishableKey = "sb_publishable_2hIDcofS47F1r64KaEIJ5g_cAEasvad"
    static let googleWebClientID = "950804556584-f88q4d63fm4hfmobhavme9p7s23af496.apps.googleusercontent.com"
    static let client = SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)
}

struct SignedInPerson: Sendable {
    var givenName: String
    var familyName: String
    var photoURL: URL?
}

enum OwnerAuth {
    @MainActor
    static func google() async throws -> SignedInPerson {
        let iosID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: iosID,
            serverClientID: TernedBackend.googleWebClientID
        )
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: try presenter())
        guard let idToken = result.user.idToken?.tokenString else { throw AuthFailure.missingToken }
        try await TernedBackend.client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
        )
        let profile = result.user.profile
        return await storedPerson(fallback: SignedInPerson(
            givenName: profile?.givenName ?? "",
            familyName: profile?.familyName ?? "",
            photoURL: profile?.imageURL(withDimension: 256)
        ))
    }

    @MainActor
    static func apple() async throws -> SignedInPerson {
        let signIn = AppleSignIn()
        activeApple = signIn
        let credential: ASAuthorizationAppleIDCredential
        do {
            credential = try await signIn.credential()
            activeApple = nil
        } catch {
            activeApple = nil
            throw error
        }
        guard let idToken = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw AuthFailure.missingToken
        }
        try await TernedBackend.client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken)
        )
        let given = credential.fullName?.givenName ?? ""
        let family = credential.fullName?.familyName ?? ""
        if given.isEmpty && family.isEmpty {
            return await storedPerson(fallback: SignedInPerson(givenName: "", familyName: "", photoURL: nil))
        }
        let userID = try await TernedBackend.client.auth.session.user.id
        try await TernedBackend.client
            .from("profiles")
            .update(ProfileName(given_name: given, family_name: family))
            .eq("id", value: userID)
            .execute()
        return await storedPerson(fallback: SignedInPerson(givenName: given, familyName: family, photoURL: nil))
    }

    @MainActor
    private static func storedPerson(fallback: SignedInPerson) async -> SignedInPerson {
        guard let user = try? await TernedBackend.client.auth.session.user else { return fallback }
        let row: ProfileRow? = try? await TernedBackend.client
            .from("profiles")
            .select("given_name,family_name,avatar_url")
            .eq("id", value: user.id)
            .single()
            .execute()
            .value
        if let row, !row.given_name.trimmingCharacters(in: .whitespaces).isEmpty {
            let photo = URL(string: row.avatar_url ?? "") ?? fallback.photoURL
            return SignedInPerson(givenName: row.given_name, familyName: row.family_name, photoURL: photo)
        }
        if !fallback.givenName.trimmingCharacters(in: .whitespaces).isEmpty { return fallback }
        let meta = user.userMetadata
        let full = meta["full_name"]?.stringValue ?? meta["name"]?.stringValue ?? ""
        let given = meta["given_name"]?.stringValue ?? full.split(separator: " ").first.map(String.init) ?? ""
        let family = meta["family_name"]?.stringValue ?? full.split(separator: " ").dropFirst().joined(separator: " ")
        let photo = URL(string: meta["avatar_url"]?.stringValue ?? meta["picture"]?.stringValue ?? "") ?? fallback.photoURL
        return SignedInPerson(givenName: given, familyName: family, photoURL: photo)
    }

    @MainActor private static var activeApple: AppleSignIn?

    static func cancelled(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain && ns.code == ASAuthorizationError.canceled.rawValue {
            return true
        }
        return ns.domain == "com.google.GIDSignIn" && ns.code == -5
    }

    @MainActor
    private static func presenter() throws -> UIViewController {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        guard let controller else { throw AuthFailure.missingScreen }
        return controller
    }
}

private struct ProfileName: Encodable {
    var given_name: String
    var family_name: String
}

private struct ProfileRow: Decodable {
    var given_name: String
    var family_name: String
    var avatar_url: String?
}

private enum AuthFailure: LocalizedError {
    case missingToken
    case missingScreen

    var errorDescription: String? {
        switch self {
        case .missingToken: "Apple or Google did not return a sign-in token."
        case .missingScreen: "The sign-in screen is not ready."
        }
    }
}

private final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var controller: ASAuthorizationController?

    func credential() async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            continuation?.resume(returning: credential)
        } else {
            continuation?.resume(throwing: AuthFailure.missingToken)
        }
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first ?? UIWindow()
    }
}
