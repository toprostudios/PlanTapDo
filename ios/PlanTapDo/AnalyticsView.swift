// AnalyticsView.swift
import SwiftUI

struct AnalyticsView: View {
    @ObservedObject var viewModel: TodoViewModel
    @Environment(\.dismiss) private var dismiss

    private var totalPlannedMinutes: Double {
        viewModel.todos.reduce(0) { $0 + Double($1.plannedDuration / 60) }
    }

    private var totalTrackedSeconds: Double {
        viewModel.todos.reduce(0) { acc, todo in
            acc + (todo.timeSessions ?? []).reduce(0) { sAcc, session in
                let end = session.end ?? Date()
                return sAcc + max(0, end.timeIntervalSince(session.start))
            }
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Metrics Grid Cards
                    HStack(spacing: 12) {
                        metricBox(icon: "⏱️", title: "Tracked", val: String(format: "%.1f hrs", totalTrackedSeconds / 3600))
                        metricBox(icon: "🎯", title: "Planned", val: String(format: "%.1f hrs", totalPlannedMinutes / 60))
                        metricBox(icon: "📈", title: "Ratio", val: "\(totalPlannedMinutes > 0 ? Int((totalTrackedSeconds / 60) / totalPlannedMinutes * 100) : 0)%")
                    }
                    .padding(.horizontal)

                    // Category Breakdown Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("🏷️ TRACKED TIME BY CATEGORY")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.secondary)

                        ForEach(viewModel.categories) { cat in
                            let catSec = viewModel.todos.filter { $0.categoryId == cat.id }.reduce(0) { acc, todo in
                                acc + (todo.timeSessions ?? []).reduce(0) { sAcc, s in sAcc + max(0, (s.end ?? Date()).timeIntervalSince(s.start)) }
                            }
                            let pct = totalTrackedSeconds > 0 ? (catSec / totalTrackedSeconds) : 0
                            let catColor = Color(hex: cat.colorHex)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(cat.icon ?? "") \(cat.name)")
                                        .font(.subheadline.weight(.bold))
                                    Spacer()
                                    Text(String(format: "%.1f hrs (%d%%)", catSec / 3600, Int(pct * 100)))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.secondary.opacity(0.15))
                                        Capsule().fill(catColor).frame(width: max(4, geo.size.width * CGFloat(pct)))
                                    }
                                }
                                .frame(height: 8)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03)))
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("📊 Toggl Time Analytics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private func metricBox(icon: String, title: String, val: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(icon).font(.title3)
            Text(val).font(.title3.weight(.bold)).foregroundStyle(.primary)
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
    }
}
