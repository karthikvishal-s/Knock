import PhotosUI
import SwiftUI

/// The colour choices for categories, accounts and goals. Mid-tone, so they read on both
/// light and dark backgrounds.
enum Palette {
    static let hexes: [String] = [
        "#FF453A", "#FF6B35", "#FF9F0A", "#FFD60A", "#C9E265", "#30D158",
        "#00C7BE", "#40C8E0", "#64D2FF", "#0A84FF", "#5E5CE6", "#BF5AF2",
        "#E05780", "#FF375F", "#FF8FAB", "#AC8E68", "#8D6E63", "#6D9886",
        "#7D7AFF", "#A2845E", "#98989D", "#636366", "#34C759", "#1F6FEB",
    ]
}

struct ColorPaletteGrid: View {
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Palette.hexes, id: \.self) { hex in
                Button {
                    selection = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(height: 30)
                        .overlay {
                            if hex.caseInsensitiveCompare(selection) == .orderedSame {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Colour \(hex)")
                .accessibilityAddTraits(hex.caseInsensitiveCompare(selection) == .orderedSame ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// One-emoji text field plus quick suggestions. Any emoji works via the system keyboard.
struct EmojiField: View {
    @Binding var emoji: String
    var suggestions: [String] = ["🍔", "🛒", "🚕", "⛽", "🛍️", "🧾", "🏠", "💊", "🎬", "✈️", "📚", "💇", "🎁", "🏦", "🔁", "💼", "🧑‍💻", "📈", "🐶", "☕", "🍺", "👶", "🏋️", "📱"]
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(emoji)
                    .font(.system(size: 34))
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular, in: .circle)
                TextField("Type any emoji", text: $text)
                    .onChange(of: text) { _, newValue in
                        if let last = newValue.last(where: \.isEmoji) {
                            emoji = String(last)
                        }
                        if !newValue.isEmpty { text = "" }
                    }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(suggestions, id: \.self) { option in
                        Button(option) { emoji = option }
                            .font(.title2)
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

extension Character {
    var isEmoji: Bool {
        unicodeScalars.contains { $0.properties.isEmojiPresentation } ||
            (unicodeScalars.count > 1 && unicodeScalars.contains { $0.properties.isEmoji })
    }
}

/// Picks a receipt photo and hands back compressed JPEG data (≤ 2048 px).
struct ReceiptPicker: View {
    let hasReceipt: Bool
    var onPick: (Data) -> Void

    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Label(hasReceipt ? "Replace receipt" : "Add receipt photo", systemImage: "doc.text.image")
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self), let compressed = ImageCompression.jpeg(from: data) {
                    onPick(compressed)
                }
                item = nil
            }
        }
    }
}

enum ImageCompression {
    static func jpeg(from data: Data, maxDimension: CGFloat = 2_048, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image.jpegData(compressionQuality: quality) }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
