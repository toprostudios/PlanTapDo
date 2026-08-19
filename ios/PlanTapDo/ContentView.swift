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
                        Label("Upcoming", systemImage: "calendar")
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

                if viewModel.isProReviewDemo {
                    ProTeamReviewView(viewModel: viewModel)
                        .tabItem { Label("Team", systemImage: "person.3.fill") }
                        .tag(4)
                }
            }
            .navigationTitle(navigationTitle(for: viewModel.selectedTab))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(
                viewModel.selectedTab == 0 || viewModel.selectedTab == 1 ? .hidden : .visible,
                for: .navigationBar
            )
            .accentColor(.indigo)
            .preferredColorScheme(viewModel.theme.preferredColorScheme)
            .contrast(viewModel.theme.contrastAmount)
            .dismissKeyboardWhenBackgroundTapped()
            .onAppear {
                viewModel.fetchTodos()
                viewModel.pushOverdueTasks()
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
                viewModel.pushOverdueTasks(at: now)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.canUndoLastStart {
                    StartNowUndoBar(viewModel: viewModel)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    private func navigationTitle(for tab: Int) -> String {
        switch tab {
        case 0, 1: return ""
        case 2: return "🏷️ Categories"
        case 3: return "⚙️ Settings"
        case 4: return "👥 Team"
        default: return "PlanTapDo"
        }
    }
}

private struct StartNowUndoBar: View {
    @ObservedObject var viewModel: TodoViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .foregroundStyle(.white)
            Text("Started \(viewModel.startUndoTitle ?? "task") now")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Button("Undo") {
                viewModel.undoLastStart()
            }
            .font(.caption.weight(.black))
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.indigo))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
