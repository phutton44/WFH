import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var store: AttendanceStore
    @StateObject private var googleAuth = GoogleOAuthCoordinator()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("WFH Attendance")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.primaryText)
                                .minimumScaleFactor(0.75)
                            Text("Track office days, WFH, leave, sickness, and non-working days with a native calendar built for your phone.")
                                .font(.callout)
                                .foregroundStyle(Color.primaryText.opacity(0.62))
                                .lineSpacing(3)
                        }
                        .padding(.top, 44)

                        VStack(spacing: 16) {
                            if store.isBusy {
                                ProgressView()
                                    .tint(.primary)
                            }

                            VStack(spacing: 10) {
                                Text("Continue with your ID")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    if Bundle.main.appleSignInEnabled {
                                        SignInWithAppleButton(.continue) { request in
                                            request.requestedScopes = [.email]
                                        } onCompletion: { result in
                                            Task { await store.handleAppleSignIn(result) }
                                        }
                                        .signInWithAppleButtonStyle(.white)
                                        .frame(height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }

                                    Button {
                                        Task { await signInWithGoogle() }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "g.circle.fill")
                                                .font(.title3)
                                            Text("Google")
                                                .fontWeight(.semibold)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.primaryText)
                                    .background(Color.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.borderSubtle, lineWidth: 1)
                                    )
                                }
                                .disabled(store.isBusy)
                            }
                        }
                        .padding(20)
                        .glassPanel(cornerRadius: 30)
                    }
                    .padding(22)
                }
            }
        }
    }

    private func signInWithGoogle() async {
        do {
            let idToken = try await googleAuth.signIn()
            await store.signInWithGoogle(idToken: idToken)
        } catch {
            store.presentError(error.localizedDescription)
        }
    }
}
