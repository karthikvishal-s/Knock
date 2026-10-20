import KnockKit
import SwiftData
import SwiftUI

struct TagsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerTag.name) private var tags: [LedgerTag]
    @State private var newName = ""
    @State private var renaming: LedgerTag?
    @State private var renameText = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("New tag", text: $newName)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Tags cut across categories — e.g. “work trip” or “wedding”. Add them in a transaction's editor.")
            }
            Section {
                if tags.isEmpty {
                    Text("No tags yet").foregroundStyle(.secondary)
                }
                ForEach(tags) { tag in
                    HStack {
                        Label(tag.name, systemImage: "number")
                        Spacer()
                        Text("\(tag.entries?.count ?? 0)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { try? TagService(context: context).delete(tag) }
                        Button("Rename", systemImage: "pencil") {
                            renameText = tag.name
                            renaming = tag
                        }
                    }
                }
            }
        }
        .navigationTitle("Tags")
        .alert("Rename tag", isPresented: .constant(renaming != nil)) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let renaming { try? TagService(context: context).rename(renaming, to: renameText) }
                renaming = nil
            }
        }
    }

    private func add() {
        _ = try? TagService(context: context).findOrCreate(named: newName)
        newName = ""
    }
}

/// Multi-select tag chips with inline creation, for the transaction editor.
struct TagPicker: View {
    @Binding var selection: [UUID]
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerTag.name) private var tags: [LedgerTag]
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags) { tag in
                        let isOn = selection.contains(tag.id)
                        Button {
                            if isOn { selection.removeAll { $0 == tag.id } } else { selection.append(tag.id) }
                        } label: {
                            Text("#\(tag.name)")
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isOn ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.fill.tertiary), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }
            HStack {
                TextField("New tag", text: $newName)
                    .onSubmit(create)
                Button("Add", action: create)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func create() {
        if let tag = try? TagService(context: context).findOrCreate(named: newName), !selection.contains(tag.id) {
            selection.append(tag.id)
        }
        newName = ""
    }
}

/// Wraps children onto new lines, like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
