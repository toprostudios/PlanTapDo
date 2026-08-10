// ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TodoViewModel()

    var body: some View {
        NavigationStack {
            TabView(selection: $viewModel.selectedTab) {
                TodayView(viewModel: viewModel)
                    .tabItem {
                        Label("Today", systemImage: "pin.fill")
                    }
                    .tag(0)

                FutureView(viewModel: viewModel)
                    .tabItem {
                        Label("Future", systemImage: "calendar")
                    }
                    .tag(1)

                CategoriesView(viewModel: viewModel)
                    .tabItem {
                        Label("Categories", systemImage: "tag.fill")
                    }
                    .tag(2)

                SettingsView(viewModel: viewModel)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(3)
            }
            .navigationTitle(navigationTitle(for: viewModel.selectedTab))
            .navigationBarTitleDisplayMode(.inline)
            .accentColor(.indigo)
            .preferredColorScheme(viewModel.theme == .dark ? .dark : (viewModel.theme == .light ? .light : .dark))
            .onAppear {
                viewModel.fetchTodos()
            }
        }
    }

    private func navigationTitle(for tab: Int) -> String {
        switch tab {
        case 0: return "📍 Today"
        case 1: return "🗓️ Future"
        case 2: return "🏷️ Categories"
        case 3: return "⚙️ Settings"
        default: return "PlanTapDo"
        }
    }
}

#Preview {
    ContentView()
}
