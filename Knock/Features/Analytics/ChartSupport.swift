import Accessibility
import Charts
import KnockKit
import SwiftUI

/// Chart colours. Series colours come from the validated reference palette (slots 1 and 3
/// pass colour-blind separation in both modes); dark mode uses its own steps, not a flip.
enum ChartColors {
    static let spend = dynamic(light: "#2a78d6", dark: "#3987e5")
    static let income = dynamic(light: "#1baf7a", dark: "#199e70")
    static let other = dynamic(light: "#a3a29c", dark: "#6f6e69")

    /// Sequential single-hue ramp for the heatmap (light → dark = less → more).
    static func heat(_ level: Int) -> Color {
        level == 0 ? Color(.tertiarySystemFill) : spend.opacity([0, 0.25, 0.45, 0.7, 1][min(level, 4)])
    }

    private static func dynamic(light: String, dark: String) -> Color {
        Color(UIColor { traits in UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light)) })
    }
}

/// Short axis labels: ₹950, ₹12K, ₹1.2L (locale-aware compact notation).
func compactMoney(_ minor: Int64, currencyCode: String) -> String {
    let value = Money(minorUnits: minor, currencyCode: currencyCode).amount
    let magnitude = (value < 0 ? -value : value).formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    return (value < 0 ? "−" : "") + MoneyFormat.symbol(for: currencyCode) + magnitude
}

extension Int64 {
    var rupees: Double { Double(self) / 100 }
}

/// A titled card that holds one chart or list.
struct ChartCard<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

/// VoiceOver audio-graph description for a single-series chart over dates.
struct SeriesChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let points: [(date: Date, value: Double)]
    let valueTitle: String
    let dateStyle: Date.FormatStyle

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = points.map(\.value)
        let minValue = min(values.min() ?? 0, 0)
        let maxValue = max(values.max() ?? 0, 1)
        let xAxis = AXCategoricalDataAxisDescriptor(title: String(localized: "Date"), categoryOrder: points.map { $0.date.formatted(dateStyle) })
        let yAxis = AXNumericDataAxisDescriptor(title: valueTitle, range: minValue...maxValue, gridlinePositions: []) { value in
            value.formatted(.number.precision(.fractionLength(0)))
        }
        let series = AXDataSeriesDescriptor(name: title, isContinuous: false, dataPoints: points.map {
            AXDataPoint(x: $0.date.formatted(dateStyle), y: $0.value)
        })
        return AXChartDescriptor(title: title, summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}
