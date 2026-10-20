import KnockKit
import SwiftData
import SwiftUI

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerCategory.sortOrder) private var all: [LedgerCategory]

    @State private var kind: CategoryKind = .expense
    @State private var editing: LedgerCategory?
    @State private var adds = false
    @State private var errorMessage: String?

    private var service: CategoryService { CategoryService(context: context) }
    private var active: [LedgerCategory] { all.filter { $0.kind == kind && !$0.isArchived } }
    private var archived: [LedgerCategory] { all.filter { $0.kind == kind && $0.isArchived } }

    var body: some View {
        List {
            Section {
                Picker("Kind", selection: $kind) {
                    Text("Expense").tag(CategoryKind.expense)
                    Text("Income").tag(CategoryKind.income)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                ForEach(active) { category in
                    Button { editing = category } label: { CategoryRow(category: category) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Archive", systemImage: "archivebox") { setArchived(category, true) }
                                .tint(.orange)
                        }
                }
                .onMove(perform: move)
            } footer: {
                Text("Drag to reorder. Archived categories keep their history but disappear from pickers.")
            }

            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { category in
                        CategoryRow(category: category)
                            .opacity(0.6)
                            .swipeActions {
                                Button("Restore", systemImage: "arrow.uturn.backward") { setArchived(category, false) }
                                    .tint(.green)
                            }
                    }
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { adds = true }
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(isPresented: $adds) { CategoryEditor(category: nil, kind: kind) }
        .sheet(item: $editing) { CategoryEditor(category: $0, kind: $0.kind) }
        .alert("Couldn't update category", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func setArchived(_ category: LedgerCategory, _ archived: Bool) {
        do { try service.setArchived(category, archived) } catch { errorMessage = error.localizedDescription }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = active.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        do { try service.reorder(ids + archived.map(\.id), kind: kind) } catch { errorMessage = error.localizedDescription }
    }
}

private struct CategoryRow: View {
    let category: LedgerCategory

    var body: some View {
        HStack(spacing: 12) {
            if category.parent != nil {
                Spacer().frame(width: 16)
            }
            CategoryBadge(emoji: category.emoji, colorHex: category.colorHex, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                if let parent = category.parent {
                    Text("in \(parent.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(category.entries?.count ?? 0)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(category.entries?.count ?? 0) transactions")
        }
        .contentShape(.rect)
    }
}

struct CategoryEditor: View {
    let category: LedgerCategory?
    let kind: CategoryKind

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerCategory.sortOrder) private var all: [LedgerCategory]

    @State private var draft: CategoryDraft
    @State private var merges = false
    @State private var confirmsDelete = false
    @State private var errorMessage: String?

    init(category: LedgerCategory?, kind: CategoryKind) {
        self.category = category
        self.kind = kind
        _draft = State(initialValue: category.map(CategoryDraft.init(category:)) ?? CategoryDraft(colorHex: Palette.hexes.randomElement() ?? "#8E8E93", kind: kind))
    }

    private var service: CategoryService { CategoryService(context: context) }

    /// Top-level categories of the same kind, excluding this one.
    private var parentOptions: [LedgerCategory] {
        all.filter { $0.kind == kind && $0.parent == nil && $0.id != category?.id && !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                    if (category?.children ?? []).isEmpty {
                        Picker("Inside", selection: $draft.parentID) {
                            Text("None (top level)").tag(UUID?.none)
                            ForEach(parentOptions) { Text($0.displayName).tag(Optional($0.id)) }
                        }
                    }
                }
                Section("Emoji") {
                    EmojiField(emoji: $draft.emoji)
                }
                Section("Colour") {
                    ColorPaletteGrid(selection: $draft.colorHex)
                }
                if let category {
                    Section {
                        Button("Merge into…", systemImage: "arrow.triangle.merge") { merges = true }
                        Button(category.isArchived ? "Restore" : "Archive", systemImage: "archivebox") {
                            perform { try service.setArchived(category, !category.isArchived) }
                        }
                        if (category.entries ?? []).isEmpty {
                            Button("Delete", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                        }
                    } footer: {
                        Text("Merging moves all \(category.entries?.count ?? 0) transactions, budgets and rules to the other category, then removes this one.")
                    }
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) {
                        perform {
                            if let category { try service.update(category, with: draft) } else { try service.add(draft) }
                        }
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $merges) {
                if let category {
                    MergePicker(source: category, candidates: all.filter { $0.kind == kind && $0.id != category.id && !$0.isArchived }) { target in
                        perform { try service.merge(category, into: target) }
                    }
                }
            }
            .confirmationDialog("Delete this category?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let category { perform { try service.delete(category) } }
                }
            }
            .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MergePicker: View {
    let source: LedgerCategory
    let candidates: [LedgerCategory]
    var onPick: (LedgerCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var target: LedgerCategory?

    var body: some View {
        NavigationStack {
            List(candidates) { candidate in
                Button {
                    target = candidate
                } label: {
                    HStack {
                        Text(candidate.displayName).foregroundStyle(.primary)
                        Spacer()
                        if candidate.id == target?.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
            }
            .navigationTitle("Merge \(source.name) into")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge", role: .confirm) {
                        if let target {
                            dismiss()
                            onPick(target)
                        }
                    }
                    .disabled(target == nil)
                }
            }
        }
    }
}

#Preview {
    NavigationStack { CategoriesView() }
        .previewEnvironment()
}
