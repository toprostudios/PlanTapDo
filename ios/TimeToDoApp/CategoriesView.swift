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

    private let colorSwatches = ["7C6FF7", "3ECF8E", "F5A623", "60A5FA", "EC4899", "F43F5E", "EAB308", "14B8A6"]

    @State private var successBanner = false

    private var activeCategory: Category? {
        if let id = selectedCatId {
            return viewModel.categories.first { $0.id == id }
        }
        return viewModel.categories.first
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header Bar with Settings Button
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🏷️ Categories & Notion Canvas")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("Custom category colors & Notion document views")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        viewModel.showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.indigo))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 16) {
                        // Horizontal Category Color Pill Selector
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.categories) { cat in
                                    let isSelected = (activeCategory?.id == cat.id)
                                    let catColor = Color(hex: cat.colorHex)

                                    Button {
                                        selectedCatId = cat.id
                                    } label: {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(catColor)
                                                .frame(width: 10, height: 10)
                                            Text("\(cat.icon ?? "") \(cat.name)")
                                                .font(.subheadline.weight(.bold))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule().fill(isSelected ? catColor : Color.secondary.opacity(0.15))
                                        )
                                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button {
                                    showingAddCategory.toggle()
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.subheadline.weight(.bold))
                                        .padding(8)
                                        .background(Circle().fill(Color.indigo.opacity(0.2)))
                                        .foregroundStyle(.indigo)
                                }
                            }
                            .padding(.horizontal)
                        }

                        if showingAddCategory {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Category Name", text: $newCatName)
                                    .textFieldStyle(.roundedBorder)

                                Text("Select Category Color:").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    ForEach(colorSwatches, id: \.self) { hex in
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 24, height: 24)
                                            .overlay(
                                                Circle().stroke(Color.white, lineWidth: newCatHex == hex ? 3 : 0)
                                            )
                                            .onTapGesture {
                                                newCatHex = hex
                                            }
                                    }
                                }

                                HStack {
                                    TextField("Icon (e.g. 🎯)", text: $newCatIcon)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 100)
                                    Button("Save Category") {
                                        guard !newCatName.isEmpty else { return }
                                        viewModel.addCategory(name: newCatName, colorHex: newCatHex, icon: newCatIcon)
                                        newCatName = ""
                                        showingAddCategory = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.indigo)
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
                            .padding(.horizontal)
                        }

                        // Mode Segmented Picker: Notion Document Canvas vs Create Task Form
                        Picker("Category Mode", selection: $activeSubTab) {
                            Text("📝 Notion Canvas").tag(0)
                            Text("➕ Create Task").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        if activeSubTab == 0, let cat = activeCategory {
                            let catColor = Color(hex: cat.colorHex)

                            // Notion-Style Document Editor View
                            VStack(alignment: .leading, spacing: 14) {
                                // Notion Banner & Header styled with Category Color
                                HStack(spacing: 12) {
                                    Text(cat.icon ?? "📝")
                                        .font(.system(size: 32))
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(catColor.opacity(0.2)))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(cat.name) Notion Canvas")
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(catColor)
                                        Text("Autosaved category document notes & checklists")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Divider()

                                // Quick Markdown Block Buttons
                                HStack(spacing: 8) {
                                    Button("H1") { insertBlock("# ", for: cat) }
                                    Button("H2") { insertBlock("## ", for: cat) }
                                    Button("☑️ Task") { insertBlock("- [ ] ", for: cat) }
                                    Button("• Bullet") { insertBlock("- ", for: cat) }
                                    Button("💬 Quote") { insertBlock("> ", for: cat) }
                                }
                                .font(.caption2.weight(.bold))
                                .buttonStyle(.bordered)

                                // Notion Text Canvas
                                TextEditor(text: Binding(
                                    get: { getCatNotes(cat) },
                                    set: { newNotes in setCatNotes(newNotes, for: cat) }
                                ))
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 350)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(catColor.opacity(0.4)))
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03)))
                            .padding(.horizontal)
                        } else {
                            // Task Entry Form Panel
                            VStack(alignment: .leading, spacing: 16) {
                                Text("➕ ENTER NEW TASK")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(.secondary)

                                if successBanner {
                                    Text("✅ Task Created Successfully!")
                                        .font(.callout.weight(.bold))
                                        .foregroundStyle(.green)
                                        .padding(10)
                                        .frame(maxWidth: .infinity)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.15)))
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Task Title *").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    TextField("e.g. Complete quarterly roadmap review", text: $title)
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))

                                    Text("Description (Optional)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    TextField("Add notes or context...", text: $description)
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
                                }

                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Do Date").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                        DatePicker("", selection: $doDate, displayedComponents: .date)
                                            .labelsHidden()
                                    }
                                    Spacer()
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Start Time").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                        TextField("09:00", text: $plannedStartTime)
                                            .frame(width: 80)
                                            .padding(8)
                                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Descriptive Deadline (No effect on calendar view)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    TextField("e.g. Before client sync / By 5:00 PM", text: $descriptiveDeadline)
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))

                                    HStack {
                                        Text("Priority Level").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                        Spacer()
                                        Picker("Priority", selection: $priority) {
                                            ForEach(PriorityLevel.allCases) { p in
                                                Text(p.badgeText).tag(p)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(width: 220)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Location (Auto-adds transit time between different locations)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    TextField("e.g. HQ Office, Gym, Home", text: $location)
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))

                                    Text("Labels / Tags (Comma separated)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    TextField("e.g. product, roadmap, urgent", text: $labelsStr)
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Duration (Minutes)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    HStack(spacing: 8) {
                                        ForEach([15, 30, 45, 60, 90, 120], id: \.self) { mins in
                                            let isSelected = plannedDurationMinutes == mins
                                            Button {
                                                plannedDurationMinutes = mins
                                            } label: {
                                                Text(mins >= 60 ? "\(mins / 60)h" : "\(mins)m")
                                                    .font(.caption.weight(.bold))
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.indigo : Color.secondary.opacity(0.15)))
                                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }

                                Button {
                                    guard !title.isEmpty else { return }
                                    let labels = labelsStr.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

                                    viewModel.createTodo(
                                        title: title,
                                        description: description.isEmpty ? nil : description,
                                        doDate: doDate,
                                        dueDate: hasDueDate ? dueDate : nil,
                                        dueTime: dueTime,
                                        descriptiveDeadline: descriptiveDeadline.isEmpty ? nil : descriptiveDeadline,
                                        plannedStartTime: plannedStartTime,
                                        plannedDuration: TimeInterval(plannedDurationMinutes * 60),
                                        categoryId: activeCategory?.id ?? viewModel.categories.first?.id,
                                        priority: priority,
                                        location: location.isEmpty ? nil : location,
                                        reminder: reminder,
                                        labels: labels.isEmpty ? nil : labels
                                    )
                                    title = ""
                                    description = ""
                                    descriptiveDeadline = ""
                                    location = ""
                                    labelsStr = ""
                                    successBanner = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        successBanner = false
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Create Task")
                                    }
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
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03)))
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 30)
                }
                .background(Color.primary.opacity(0.02).ignoresSafeArea())
                #if os(iOS)
                .navigationBarHidden(true)
                #endif
                .sheet(isPresented: $viewModel.showingSettings) {
                    SettingsView(viewModel: viewModel)
                }
            }
            #if os(iOS)
            .navigationViewStyle(.stack)
            #endif
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
