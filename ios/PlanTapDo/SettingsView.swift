// SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: TodoViewModel

    var body: some View {
        Form {
            Section("👤 Personal Account") {
                NavigationLink {
                    AccountView(viewModel: viewModel)
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.indigo)
                            .frame(width: 38, height: 38)
                            .overlay {
                                Text(viewModel.userAccount.name.prefix(1).uppercased())
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.userAccount.name)
                                .font(.subheadline.weight(.bold))
                            Text(viewModel.userAccount.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(viewModel.userAccount.isCloudSynced ? "Cloud sync is active." : "This personal account is using local demo data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("🎨 Appearance & Readability") {
                Picker("Theme", selection: $viewModel.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("💾 Local Data") {
                Text("Reload the personal sample tasks, calendar blocks, and categories.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.loadSampleData()
                } label: {
                    Label("Reload Sample Tasks & Categories", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.indigo)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

#Preview("Settings View") {
    SettingsView(viewModel: TodoViewModel())
}
