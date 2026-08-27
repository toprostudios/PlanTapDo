// PlanTapDo.swift
import SwiftUI

@main
struct PlanTapDoApp: App {
    @StateObject private var subscriptionManager = SubscriptionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(subscriptionManager)
        }
    }
}
