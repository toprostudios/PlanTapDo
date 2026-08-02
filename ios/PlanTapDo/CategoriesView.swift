// CategoriesView.swift
import SwiftUI

struct CategoriesView: View {
    @ObservedObject var viewModel: TodoViewModel

    @State private var selectedCatId: UUID? = nil
    @State private var activeSubTab: Int = 0 // 0: Notion Document, 1: Add Task Form

    // Task entry form state
    @State private var title = ""
    @State private var description = ""
    @State private var doDate = Date()
    @State private var dueDate = Date()
    @State private var hasDueDate = true
    @State private var dueTime = "18:00"
    @State private var descriptiveDeadline = ""
    @State private var plannedStartTime = "09:00"
    @State private var plannedDurationMinutes = 30
    @State private var priority: PriorityLevel = .medium
    @State private var location = ""
    @State private var reminder = "15 minutes before"
    @State private var labelsStr = ""

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
                            let newCat = Category(id: UUID(), name: newCatName, colorHex: newCatHex, icon: newCatIcon)
                            viewModel.categories.append(newCat)
                            selectedCatId = newCat.id
                            newCatName = ""
                            showingAddCategory = false
                        }
                    )
                }

                // Subtab Header: Notion Document vs Add Task Form
                HStack(spacing: 0) {
                    Button {
                        activeSubTab = 0
                    } label: {
                        VStack(spacing: 6) {
                            Label("Notion Document", systemImage: "doc.plaintext")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(activeSubTab == 0 ? .indigo : .secondary)
                            Rectangle()
                                .fill(activeSubTab == 0 ? Color.indigo : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        activeSubTab = 1
                    } label: {
                        VStack(spacing: 6) {
                            Label("Task Entry Form", systemImage: "plus.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(activeSubTab == 1 ? .indigo : .secondary)
                            Rectangle()
                                .fill(activeSubTab == 1 ? Color.indigo : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)

                // Subtab Content
                if activeSubTab == 0 {
                    // Notion Canvas View
                    VStack(alignment: .leading, spacing: 14) {
                        if let activeCat = activeCategory {
                            // Cover Banner Card
                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: activeCat.colorHex).opacity(0.6), Color(hex: activeCat.colorHex).opacity(0.15)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(height: 100)

                                HStack(spacing: 10) {
                                    Text(activeCat.icon ?? "🔖")
                                        .font(.system(size: 32))
                                        .padding(8)
                                        .background(Circle().fill(Color.white.opacity(0.9)))

                                    Text(activeCat.name)
                                        .font(.title2.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                                .padding(12)
                            }
                            .padding(.horizontal)

                            // Quick Insert Toolbar
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    Button("+ Heading") { insertBlock("# ", for: activeCat) }
                                    Button("+ Bullet") { insertBlock("• ", for: activeCat) }
                                    Button("+ Todo") { insertBlock("[ ] ", for: activeCat) }
                                    Button("+ Quote") { insertBlock("> ", for: activeCat) }
                                    Button("+ Code") { insertBlock("```\n\n```", for: activeCat) }
                                }
                                .font(.caption.weight(.bold))
                                .buttonStyle(.bordered)
                                .tint(.indigo)
                                .padding(.horizontal)
                            }

                            // Editable Text Area for Category Notes
                            VStack(alignment: .leading, spacing: 4) {
                                Text("NOTION NOTES CANVAS")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(.secondary)

                                TextEditor(text: Binding(
                                    get: { getCatNotes(activeCat) },
                                    set: { setCatNotes($0, for: activeCat) }
                                ))
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 280)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray).opacity(0.15))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))

                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                } else {
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
                            Text("CREATE TASK")
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
                                    plannedStartTime: plannedStartTime,
                                    plannedDuration: TimeInterval(plannedDurationMinutes * 60),
                                    categoryId: activeCategory?.id ?? viewModel.categories.first?.id,
                                    priority: priority,
                                    location: location.isEmpty ? nil : location
                                )
                                title = ""
                                description = ""
                                location = ""
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

    private func getCatNotes(_ cat: Category) -> String {
        return cat.notes ?? "# \(cat.icon ?? "") \(cat.name) Notes\n\nType notes here..."
    }

    private func setCatNotes(_ notes: String, for cat: Category) {
        if let idx = viewModel.categories.firstIndex(where: { $0.id == cat.id }) {
            viewModel.categories[idx].notes = notes
        }
    }

    private func insertBlock(_ prefix: String, for cat: Category) {
        let current = getCatNotes(cat)
        let updated = current.isEmpty ? prefix : "\(current)\n\(prefix)"
        setCatNotes(updated, for: cat)
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
