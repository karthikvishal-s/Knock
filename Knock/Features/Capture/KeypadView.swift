import KnockKit
import SwiftUI

/// A calculator-style glass keypad that edits an `AmountInput`.
struct KeypadView: View {
    @Binding var input: AmountInput
    @Environment(\.locale) private var locale

    private enum Key: Hashable {
        case digit(Int)
        case separator
        case delete
    }

    private let rows: [[Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.separator, .digit(0), .delete],
    ]

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: Key) -> some View {
        switch key {
        case .digit(let digit):
            Button {
                input.append(digit: digit)
            } label: {
                keyLabel(Text(digit, format: .number))
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("key-\(digit)")
        case .separator:
            Button {
                input.appendDecimalSeparator()
            } label: {
                keyLabel(Text(locale.decimalSeparator ?? "."))
            }
            .buttonStyle(.glass)
            .disabled(input.fractionDigits == 0)
            .accessibilityLabel("Decimal point")
            .accessibilityIdentifier("key-separator")
        case .delete:
            Button {
                input.deleteLast()
            } label: {
                keyLabel(Image(systemName: "delete.left"))
            }
            .buttonStyle(.glass)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in input.clear() })
            .accessibilityLabel("Delete")
            .accessibilityHint("Long-press to clear")
            .accessibilityIdentifier("key-delete")
        }
    }

    private func keyLabel(_ content: some View) -> some View {
        content
            .font(.title2.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

#Preview {
    @Previewable @State var input = AmountInput()
    VStack {
        Text(input.display())
            .font(.largeTitle)
        KeypadView(input: $input)
    }
    .padding()
}
