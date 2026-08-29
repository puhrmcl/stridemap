import SwiftUI

/// A calm welcome screen. Apple Health is the primary way in; Strava is an optional
/// enhancement. Either path (or simply continuing) leads to the map.
struct OnboardingView: View {
    @Environment(StravaAuthService.self) private var auth
    @Environment(HealthKitService.self) private var healthKit

    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false

    @State private var isWorking = false
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

                    Text("Etch")
                        .font(.etch(size: 40, weight: .bold))

                    Text("Every run you've ever taken,\nwoven into one living map.")
                        .font(.etch(.title3))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Spacer()

                VStack(spacing: 14) {
                    healthButton

                    stravaButton

                    Text("Your runs come from Apple Health — including workouts from Nike Run Club, Garmin, COROS, Strava, and more. Nothing is shared.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 46)
            }
            .padding()
        }
        .alert("Something Went Wrong", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var healthButton: some View {
        Button {
            Task { await connectHealth() }
        } label: {
            HStack(spacing: 10) {
                if isWorking { ProgressView().tint(.white) }
                else { Image(systemName: "heart.fill") }
                Text(isWorking ? "Connecting…" : "Connect Apple Health")
                    .font(.etch(.headline))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Theme.accent, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(isWorking || !healthKit.isAvailable)
    }

    private var stravaButton: some View {
        Button {
            Task { await connectStrava() }
        } label: {
            Text("Connect Strava (optional)")
                .font(.etch(.subheadline, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .glassBackground(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private func connectHealth() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await healthKit.requestAuthorization()
            didCompleteOnboarding = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func connectStrava() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.signIn()
            didCompleteOnboarding = true
        } catch {
            if case StravaAuthService.AuthError.cancelled = error { return }
            errorMessage = error.localizedDescription
        }
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [Theme.accent.opacity(0.18), Color.clear, Color.clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .background(Color(.systemBackground))
    }
}
