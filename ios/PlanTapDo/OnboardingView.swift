import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var page = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.95), Color(red: 0.08, green: 0.09, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                TabView(selection: $page) {
                    OnboardingPage(icon: "checklist.checked", title: "Plan your day with clarity", detail: "Capture tasks quickly, then decide what deserves your time.")
                        .tag(0)
                    OnboardingPage(icon: "calendar", title: "Make time for what matters", detail: "Schedule tasks on a calm, focused daily calendar when you’re ready.")
                        .tag(1)
                    OnboardingPage(icon: "timer", title: "Stay focused, not busy", detail: "Start a task, track your time, and learn how your weeks actually go.")
                        .tag(2)
                    SubscriptionOfferView(onSubscribed: { hasCompletedOnboarding = true })
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? .white : .white.opacity(0.35))
                            .frame(width: index == page ? 24 : 8, height: 8)
                    }
                }

                if page < 3 {
                    Button(page == 2 ? "Continue" : "Next") {
                        withAnimation { page += 1 }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 28)
        }
        .foregroundStyle(.white)
    }
}

private struct OnboardingPage: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 68, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 152, height: 152)
                .background(Circle().fill(.white.opacity(0.14)))
            VStack(spacing: 14) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(.horizontal, 36)
            Spacer()
        }
    }
}

struct SubscriptionOfferView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    let onSubscribed: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .semibold))
            Text("Unlock PlanTapDo Advanced")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Advanced currently unlocks unlimited categories.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 12) {
                Label("Advanced feature", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
                Label("Unlimited categories", systemImage: "checkmark.circle.fill")
                Text("Free plan: \(TodoViewModel.freeCategoryLimit) categories.")
                Text("Tasks, calendar planning, and timers are free.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .font(.subheadline.weight(.medium))
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.12)))
            .padding(.horizontal, 24)

            if let errorMessage = subscriptionManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 28)
            }

            ForEach(SubscriptionManager.AdvancedPlan.allCases) { plan in
                Button {
                    Task {
                        await subscriptionManager.purchase(plan)
                        if subscriptionManager.hasAdvanced { onSubscribed() }
                    }
                } label: {
                    Text("\(plan.title) — \(plan.fallbackPrice)")
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .padding(.horizontal, 24)
                .disabled(subscriptionManager.isLoading || !subscriptionManager.isAvailable(for: plan))
            }

            HStack(spacing: 24) {
                Button("Restore Purchase") {
                    Task {
                        await subscriptionManager.restorePurchases()
                        if subscriptionManager.hasAdvanced { onSubscribed() }
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
                .disabled(subscriptionManager.isLoading)

                Button("Skip for now") {
                    onSubscribed()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
            }
            Spacer()
        }
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(Color.indigo)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}
