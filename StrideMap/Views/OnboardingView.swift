import SwiftUI

/// A calm, single-purpose welcome screen: connect Strava to begin.
struct OnboardingView: View {
    @Environment(StravaAuthService.self) private var auth

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 18) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(Theme.accent)
                        .shadow(color: Theme.accent.opacity(0.4), radius: 24)

                    Text("StrideMap")
                        .font(.system(size: 40, weight: .bold, design: .rounded))

                    Text("Every run you've ever taken,\nwoven into one living map.")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Spacer()

                VStack(spacing: 14) {
                    connectButton

                    if !StravaConfig.isConfigured {
                        Text("Add your Strava keys in StravaConfig.swift to connect.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text("We only ever read your activities. Nothing is shared.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
            .padding()
        }
        .alert("Couldn't Connect", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var connectButton: some View {
        Button {
            Task { await signIn() }
        } label: {
            HStack(spacing: 10) {
                if isSigningIn {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "figure.run")
                }
                Text(isSigningIn ? "Connecting…" : "Connect with Strava")
                    .font(.system(.headline, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Theme.accent, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(isSigningIn)
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [
                Theme.accent.opacity(0.18),
                Color.clear,
                Color.clear,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .background(Color(.systemBackground))
    }

    private func signIn() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await auth.signIn()
        } catch {
            if case StravaAuthService.AuthError.cancelled = error { return }
            errorMessage = error.localizedDescription
        }
    }
}
