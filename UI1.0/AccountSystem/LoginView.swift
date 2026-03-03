//
//  NewGoogleSignIn.swift
//  audi2
//
//  Created by Sebastian Zimmerman on 2/26/26.
//

import GoogleSignIn
import GoogleSignInSwift
import SwiftUI
import _AuthenticationServices_SwiftUI

func googleSignInButton() -> some View {
    return GoogleSignInButton(scheme: .dark, style: .wide) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { signInResult, error in
            guard signInResult != nil else {
                return
            }
        }
    }
}
func appleSignInButton() -> some View {
    return SignInWithAppleButton { request in
        request.requestedScopes = [.fullName, .email]
    } onCompletion: { result in
        switch result {
        case .success(_):
            guard let windowScene = UIApplication.shared.connectedScenes as? UIWindowScene, let rootVC = windowScene.windows.first?.rootViewController else { return }
            
        case .failure(_):
            print("failed")
        }
    }
}
struct loginView: View {
    @State var email: String = ""
    @State var password: String = ""
    @Environment(\.colorScheme) var colorScheme
    let width: CGFloat = 300.0
    let height: CGFloat = 100.0
    var body: some View {
        VStack(spacing: 20) {
            if colorScheme == .dark {
                Image("banner_dark_mode1")
                    .resizable()
                    .frame(width: width, height: height)
            } else {
                Image("banner_light_mode1")
                    .resizable()
                    .frame(width: width, height: height)
            }
            Text("Login")
                .font(.system(.largeTitle, design: .monospaced))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.25, green: 0.0, blue: 1.5), Color(red: 0.2, green: 0.6, blue: 0.9), Color(red: 0.3, green: 0.6, blue: 0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
                .padding(.bottom, 30)
            HStack {
                VStack(spacing: 16){
                    HStack {
                        Image(systemName: "envelope")
                        TextField("Email", text: $email)
                            .textFieldStyle(.plain)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    HStack {
                        Image(systemName: "lock")
                        SecureField("Password", text: $password)
                        .textFieldStyle(.plain)
                        .autocapitalization(.none)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                }
            }
            Group {
                ZStack(alignment: .bottomTrailing) {
                
                Button("Login") {
                    
                    if email != "" && password != "" {
                        print("nice")
                    }
                }
                .frame(width: 200, height: 30)
                
                .border(colorScheme == .dark ? .white : .black)
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .background(colorScheme == .dark ? .black : .white)
                .padding()
            }
                Text("-Or-")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.25, green: 0.0, blue: 1.5), Color(red: 0.2, green: 0.6, blue: 0.9), Color(red: 0.3, green: 0.6, blue: 0.85)], startPoint: .leading,
                                endPoint: .trailing
                        )
                    )
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                Button("Sign Up") {
                    print("hello")
                }
                .frame(width: 200, height: 42)
                .border(colorScheme == .dark ? .white : .black)
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .background(colorScheme == .dark ? .black : .white)
                googleSignInButton()
                    .frame(width: 200, height: 42)
                appleSignInButton()
                    .frame(width: 200, height: 42)
            }
            
        }
    }
}

#Preview {
    loginView()
}
