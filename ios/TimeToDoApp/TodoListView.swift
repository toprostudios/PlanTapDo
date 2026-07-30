// TodoListView.swift
import SwiftUI

/// Legacy Todo List View wrapper - forwards to TodayView
struct LegacyTodoListView: View {
    @ObservedObject var viewModel: TodoViewModel

    var body: some View {
        TodayView(viewModel: viewModel)
    }
}
