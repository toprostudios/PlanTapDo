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

                TeamView(viewModel: viewModel)
                    .tabItem {
                        Label("Team", systemImage: "person.3.fill")
                    }
                    .tag(3)
            }
            .navigationTitle(navigationTitle(for: viewModel.selectedTab))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.showingAccountModal = true
                    } label: {
                        HStack(spacing: 5) {
                            Text("👤 \(viewModel.userAccount.name)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("👑 \(viewModel.userAccount.tier)")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.indigo)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.indigo)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingSettings) {
                SettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showingAccountModal) {
                AccountView(viewModel: viewModel)
            }
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
        case 3: return "👥 Team"
        default: return "PlanTapDo"
        }
    }
}

#Preview {
    ContentView()
}
