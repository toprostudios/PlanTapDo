// AccountView.swift
import SwiftUI

struct AccountView: View {
    @ObservedObject var viewModel: TodoViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var newEmail = ""
    @State private var showingAddForm = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Active Account Profile Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(Color.indigo)
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Text(viewModel.userAccount.name.prefix(1).uppercased())
                                        .font(.title2.weight(.bold))
                                        .foregroundStyle(.white)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(viewModel.userAccount.name)
                                        .font(.headline.weight(.bold))
                                    Text("👑 \(viewModel.userAccount.tier)")
                                        .font(.caption2.weight(.heavy))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.indigo.opacity(0.2)))
                                        .foregroundStyle(.indigo)
                                }

                                Text("✉️ \(viewModel.userAccount.email)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            Text("☁️ Cloud Synced")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.green.opacity(0.15)))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05)))
                    .padding(.horizontal)

                    // Switch Accounts List Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("🔄 SWITCH ACCOUNTS")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                showingAddForm.toggle()
                            } label: {
                                Label(showingAddForm ? "Cancel" : "Add Account", systemImage: "plus")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.indigo)
                            }
                        }

                        if showingAddForm {
                            VStack(spacing: 10) {
                                TextField("Full Name", text: $newName)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Email Address", text: $newEmail)
                                    .textFieldStyle(.roundedBorder)

                                Button("Create & Sign In") {
                                    guard !newName.isEmpty && !newEmail.isEmpty else { return }
                                    viewModel.createAndSwitchAccount(name: newName, email: newEmail)
                                    newName = ""
                                    newEmail = ""
                                    showingAddForm = false
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.indigo)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
                        }

                        ForEach(viewModel.availableAccounts) { acc in
                            let isActive = (acc.id == viewModel.userAccount.id)

                            HStack {
                                Circle()
                                    .fill(isActive ? Color.indigo : Color.secondary.opacity(0.3))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Text(acc.name.prefix(1).uppercased())
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(acc.name)
                                        .font(.subheadline.weight(.bold))
                                    Text(acc.email)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if isActive {
                                    Text("Active")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.indigo)
                                } else {
                                    Button("Switch") {
                                        viewModel.switchAccount(acc)
                                    }
                                    .font(.caption.weight(.bold))
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isActive ? Color.indigo.opacity(0.1) : Color.primary.opacity(0.04))
                            )
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03)))
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("👤 User Account")
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
}

#Preview("User Account View") {
    AccountView(viewModel: TodoViewModel())
}
