// SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: TodoViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("🎨 Appearance & Readability") {
                    Picker("Theme", selection: $viewModel.theme) {
                        ForEach(AppTheme.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("💾 Sample Demo Data") {
                    Text("Reload sample tasks, calendar blocks, and categories anytime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        viewModel.loadSampleData()
                        dismiss()
                    } label: {
                        Label("Reload Sample Tasks & Categories", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.indigo)
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.bold))
                }
            }
        }
    }
}

#Preview("Settings View") {
    SettingsView(viewModel: TodoViewModel())
}
