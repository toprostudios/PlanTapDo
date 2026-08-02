// CalendarView.swift
import SwiftUI

/// Legacy Calendar View wrapper - forwards to FutureView
struct LegacyCalendarView: View {
    @ObservedObject var viewModel: TodoViewModel

    var body: some View {
        FutureView(viewModel: viewModel)
    }
}
