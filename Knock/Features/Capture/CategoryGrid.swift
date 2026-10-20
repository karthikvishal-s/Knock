import KnockKit
import SwiftUI

/// The top-ranked categories as tappable tiles, with "More" for the full list.
struct CategoryGrid: View {
    /// Already ranked, likeliest first.
    let categories: [LedgerCategory]
    @Binding var selection: UUID?
    var columns = 4
    @State private var showsAll = false

    /// One row less than the grid holds, leaving room for "More".
    private var visibleCount: Int { columns * 2 - 1 }
    private var gridItems: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 8), count: columns) }

    var body: some View {
        LazyVGrid(columns: gridItems, spacing: 8) {
            ForEach(visible) { category in
                tile(category)
            }
            if categories.count > visibleCount {
                Button {
                    showsAll = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "ellipsis")
                            .font(.title3)
                            .frame(height: 28)
                        Text("More")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                .accessibilityIdentifier("category-more")
            }
        }
        .sheet(isPresented: $showsAll) {
            CategoryPickerList(categories: categories, selection: $selection)
                .presentationDetents([.medium, .large])
        }
    }

    /// The top tiles, with the selection swapped in if it was picked from "More".
    private var visible: [LedgerCategory] {
        var top = Array(categories.prefix(visibleCount))
        if let selection, !top.contains(where: { $0.id == selection }),
           let picked = categories.first(where: { $0.id == selection }), !top.isEmpty {
            top[top.count - 1] = picked
        }
        return top
    }

    private func tile(_ category: LedgerCategory) -> some View {
        let isSelected = category.id == selection
        return Button {
            selection = isSelected ? nil : category.id
        } label: {
            VStack(spacing: 4) {
                Text(category.emoji)
                    .font(.title2)
                    .frame(height: 28)
                Text(category.name)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(Color(hex: category.colorHex).opacity(0.55)).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 14)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: category.colorHex), lineWidth: 2)
            }
        }
        .accessibilityLabel(category.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("category-\(category.name)")
    }
}

struct CategoryPickerList: View {
    let categories: [LedgerCategory]
    @Binding var selection: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(filtered) { category in
                Button {
                    selection = category.id
                    dismiss()
                } label: {
                    HStack {
                        CategoryBadge(emoji: category.emoji, colorHex: category.colorHex, size: 32)
                        Text(category.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if category.id == selection {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }

    private var filtered: [LedgerCategory] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return categories.sorted { $0.sortOrder < $1.sortOrder } }
        return categories.filter { $0.name.localizedStandardContains(query) }
    }
}
