// ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TodoViewModel()
    private let tabSwipeThreshold: CGFloat = 70

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
                        Label("Tasks", systemImage: "checklist")
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
            .toolbar(
                viewModel.selectedTab == 0 || viewModel.selectedTab == 1 ? .hidden : .visible,
                for: .navigationBar
            )
            .accentColor(.indigo)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .preferredColorScheme(viewModel.theme.preferredColorScheme)
            .dismissKeyboardWhenBackgroundTapped()
            // Keep calendar drags available to the calendar, while allowing a
            // relaxed, clearly horizontal swipe to switch tabs.
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        handleTabSwipe(value)
                    }
            )
            .onChange(of: viewModel.selectedTab) { _ in
                AppHaptics.selection()
            }
            .onAppear {
                viewModel.pushOverdueTasks()
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
                viewModel.pushOverdueTasks(at: now)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.hasTaskAddedFeedback {
                    TaskAddedFeedbackBar(title: viewModel.taskAddedFeedbackTitle ?? "task")
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                } else if viewModel.canUndoLastStart {
                    StartNowUndoBar(viewModel: viewModel)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                } else if viewModel.hasStopFeedback {
                    StopTimerFeedbackBar(title: viewModel.stopFeedbackTitle ?? "task")
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            }
        }
        .background(AppCanvasBackground())
    }

    private func handleTabSwipe(_ value: DragGesture.Value) {
        let horizontalDistance = value.translation.width
        guard abs(horizontalDistance) >= tabSwipeThreshold,
              abs(horizontalDistance) > abs(value.translation.height) * 1.15 else {
            return
        }

        if horizontalDistance < 0 {
            // A conventional left swipe moves forward: Today to Upcoming.
            if viewModel.selectedTab == 0 {
                openUpcomingOnTomorrow()
            } else if viewModel.selectedTab < 2 {
                withAnimation { viewModel.selectedTab += 1 }
            }
        } else if viewModel.selectedTab > 0 {
            withAnimation { viewModel.selectedTab -= 1 }
        }
    }

    private func openUpcomingOnTomorrow() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }

        viewModel.selectedFutureDate = tomorrow
        viewModel.currentWeekOffset = weekOffset(from: today, to: tomorrow, calendar: calendar)
        withAnimation { viewModel.selectedTab = 1 }
    }

    private func weekOffset(from today: Date, to date: Date, calendar: Calendar) -> Int {
        func startOfWeek(containing date: Date) -> Date {
            let weekday = calendar.component(.weekday, from: date)
            let daysToMonday = weekday == 1 ? -6 : 2 - weekday
            return calendar.date(byAdding: .day, value: daysToMonday, to: date) ?? date
        }

        return calendar.dateComponents(
            [.weekOfYear],
            from: startOfWeek(containing: today),
            to: startOfWeek(containing: date)
        ).weekOfYear ?? 0
    }

    private func navigationTitle(for tab: Int) -> String {
        switch tab {
        case 0, 1: return ""
        case 2: return "✓ Tasks"
        case 3: return "⚙️ Settings"
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

private struct StopTimerFeedbackBar: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "stop.fill")
            Text("Stopped \(title)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.secondary))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}

private struct TaskAddedFeedbackBar: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
            Text("Added \(title)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.green))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .accessibilityLabel("Task added: \(title)")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
