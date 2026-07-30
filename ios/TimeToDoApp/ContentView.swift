// ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TodoViewModel()

    var body: some View {
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
        .accentColor(.indigo)
        .preferredColorScheme(viewModel.theme == .dark ? .dark : (viewModel.theme == .light ? .light : .dark))
        .onAppear {
            viewModel.fetchTodos()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
