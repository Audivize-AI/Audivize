//
//  GoogleAuthView.swift
//  audi2
//
//  Created by Sebastian Zimmerman on 2/4/26.
//

import SwiftUI
import AuthenticationServices
import UIKit

private let GOOGLE_CLIENT_ID = "376114207993-63hjs5sauukj23gfs5f44ug45e25m5jn.apps.googleusercontent.com"
private let GOOGLE_REVERSED_CLIENT_ID = "com.googleusercontent.apps.376114207993-63hjs5sauukj23gfs5f44ug45e25m5jn"

struct GoogleAuthView: View {
    @State private var session: ASWebAuthenticationSession?
    private let contextProvider = AuthContextProvider()

    var body: some View {
        Button("Login with Google") {
            startGoogleLogin()
        }
        .padding()
    }

    private func startGoogleLogin() {
        let clientID = GOOGLE_CLIENT_ID
        let reversedID = GOOGLE_REVERSED_CLIENT_ID
        let redirectURI = "\(reversedID):/oauth2redirect"
        let scope = "email%20profile"
        let state = UUID().uuidString

        let authURLString =
            "https://accounts.google.com/o/oauth2/v2/auth?" +
            "client_id=\(clientID)" +
            "&redirect_uri=\(redirectURI)" +
            "&response_type=code" +
            "&scope=\(scope)" +
            "&state=\(state)" +
            "&prompt=consent"

        guard let authURL = URL(string: authURLString) else {
            print("Bad auth URL")
            return
        }

        session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: reversedID
        ) { callbackURL, error in
            if let error = error {
                print("Auth error:", error.localizedDescription)
                return
            }

            guard let url = callbackURL else {
                print("No callback URL")
                return
            }

            print("Redirect URL:", url.absoluteString)

            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                print("Authorization Code:", code)
                // send `code` to your backend to exchange for tokens
            } else {
                print("No 'code' in callback URL")
            }
        }

        session?.presentationContextProvider = contextProvider
        session?.start()
    }
}

final class AuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // iOS: grab key window from connected scenes
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        return window ?? UIWindow()
    }
}
