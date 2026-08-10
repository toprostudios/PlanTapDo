// CategoriesView.swift
import SwiftUI

struct CategoriesView: View {
    @ObservedObject var viewModel: TodoViewModel

    @State private var selectedCatId: UUID? = nil

    // Task entry form state
    @State private var title = ""
    @State private var description = ""
    @State private var doDate = Date()
    @State private var dueDate = Date()
    @State private var hasDueDate = true
    @State private var descriptiveDeadline = ""
    @State private var hasPlannedTime = false
    @State private var plannedStartTime = "09:00"
    @State private var plannedDurationMinutes = 30
    @State private var priority: PriorityLevel = .medium
    @State private var location = ""

    // New Category state
    @State private var showingAddCategory = false
    @State private var newCatName = ""
    @State private var newCatHex = "7C6FF7"
    @State private var newCatIcon = "🎯"

    @State private var successBanner = false

    private var activeCategory: Category? {
        if let id = selectedCatId {
            return viewModel.categories.first { $0.id == id }
        }
        return viewModel.categories.first
    }

    var body: some View {
        ScreenContainer(maxWidth: 700) {
            VStack(spacing: 0) {
                // Category Badges Horizontal Selector Bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.categories) { cat in
                            let isSelected = (activeCategory?.id == cat.id)
                            let count = viewModel.todos.filter { $0.categoryId == cat.id }.count

                            Button {
                                selectedCatId = cat.id
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: cat.colorHex))
                                        .frame(width: 10, height: 10)
                                    Text(cat.icon ?? "🔖")
                                    Text(cat.name)
                                        .font(.caption.weight(.bold))
                                    Text("(\(count))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color(hex: cat.colorHex).opacity(0.2) : Color.primary.opacity(0.04))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? Color(hex: cat.colorHex) : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            showingAddCategory.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("New Category")
                                    .font(.caption.weight(.bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.indigo.opacity(0.15)))
                            .foregroundStyle(.indigo)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }

                // New Category Form Inline
                if showingAddCategory {
                    AddCategoryInlineView(
                        newCatName: $newCatName,
                        newCatIcon: $newCatIcon,
                        newCatHex: $newCatHex,
                        showingAddCategory: $showingAddCategory,
                        onSave: {
                            guard !newCatName.isEmpty else { return }
                            viewModel.addCategory(name: newCatName, colorHex: newCatHex, icon: newCatIcon)
                            selectedCatId = viewModel.categories.last?.id
                            newCatName = ""
                            showingAddCategory = false
                        }
                    )
                }

                // Task Entry Form
                VStack(spacing: 14) {
                    if successBanner {
                        Text("✅ Task Added Successfully!")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.green))
                            .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("CREATE TASK FOR \(activeCategory?.name.uppercased() ?? "CATEGORY")")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.secondary)

                        TextField("Task Title...", text: $title)
                            .textFieldStyle(.roundedBorder)

                        TextField("Description / Notes...", text: $description, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.roundedBorder)

                        DatePicker("Do Date (Execution)", selection: $doDate, displayedComponents: .date)
                            .font(.subheadline)

                        Toggle("Set Due Date & Deadline", isOn: $hasDueDate)
                            .font(.subheadline.weight(.semibold))

                        if hasDueDate {
                            DatePicker("Due Date (Deadline)", selection: $dueDate, displayedComponents: .date)
                                .font(.subheadline)

                            TextField("Descriptive Deadline (e.g. Before 6 PM sync)", text: $descriptiveDeadline)
                                .textFieldStyle(.roundedBorder)
                        }

                        Toggle("Set a planned time", isOn: $hasPlannedTime)
                            .font(.subheadline.weight(.semibold))

                        if hasPlannedTime {
                            HStack {
                                Text("Planned Time:").font(.subheadline)
                                TextField("09:00", text: $plannedStartTime)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)

                                Spacer()

                                Text("Duration:").font(.subheadline)
                                Picker("Duration", selection: $plannedDurationMinutes) {
                                    Text("15m").tag(15)
                                    Text("30m").tag(30)
                                    Text("45m").tag(45)
                                    Text("60m").tag(60)
                                    Text("90m").tag(90)
                                }
                                .pickerStyle(.menu)
                            }
                        }

                        Picker("Priority", selection: $priority) {
                            Text("Low").tag(PriorityLevel.low)
                            Text("Medium").tag(PriorityLevel.medium)
                            Text("High ⚡").tag(PriorityLevel.high)
                            Text("Urgent 🔥").tag(PriorityLevel.urgent)
                        }
                        .pickerStyle(.segmented)

                        TextField("Location (e.g. Office / Zoom)", text: $location)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            guard !title.isEmpty else { return }
                            viewModel.createTodo(
                                title: title,
                                description: description.isEmpty ? nil : description,
                                doDate: doDate,
                                dueDate: hasDueDate ? dueDate : nil,
                                descriptiveDeadline: hasDueDate && !descriptiveDeadline.isEmpty ? descriptiveDeadline : nil,
                                plannedStartTime: hasPlannedTime ? plannedStartTime : nil,
                                plannedDuration: TimeInterval(plannedDurationMinutes * 60),
                                categoryId: activeCategory?.id ?? viewModel.categories.first?.id,
                                priority: priority,
                                location: location.isEmpty ? nil : location
                            )
                            title = ""
                            description = ""
                            location = ""
                            hasPlannedTime = false
                            successBanner = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                successBanner = false
                            }
                        } label: {
                            Text("Create Task")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(title.isEmpty ? Color.gray : Color(hex: activeCategory?.colorHex ?? "7C6FF7"))
                                )
                        }
                        .disabled(title.isEmpty)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.gray).opacity(0.15))
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
    }
}

// Extracted Subview for Inline Category Creation
struct AddCategoryInlineView: View {
    @Binding var newCatName: String
    @Binding var newCatIcon: String
    @Binding var newCatHex: String
    @Binding var showingAddCategory: Bool
    let onSave: () -> Void

    private let colorSwatches = ["7C6FF7", "3ECF8E", "F5A623", "60A5FA", "EC4899", "F43F5E", "EAB308", "14B8A6"]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("➕ Add Category")
                    .font(.headline.weight(.bold))
                Spacer()
                Button("Cancel") { showingAddCategory = false }
                    .font(.caption)
            }

            TextField("Category Name", text: $newCatName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Icon:").font(.caption.weight(.bold))
                TextField("Emoji", text: $newCatIcon)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(colorSwatches, id: \.self) { (hex: String) in
                        let isSel = (newCatHex == hex)
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(isSel ? Color.primary : Color.clear, lineWidth: 2))
                            .onTapGesture { newCatHex = hex }
                    }
                }
            }

            Button("Save Category", action: onSave)
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray).opacity(0.15))
        .padding(.horizontal)
        .padding(.bottom, 10)
    }
}

#Preview("Categories View") {
    CategoriesView(viewModel: TodoViewModel())
}
