import SwiftUI

// MARK: - Card container

struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    var tint: Color
    /// Fill the height offered by the parent. Grid cells use this so every card in a row
    /// ends at the same line and the gaps between rows stay even.
    var stretch: Bool
    var accessory: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String? = nil,
         systemImage: String? = nil,
         tint: Color = .accentColor,
         stretch: Bool = false,
         accessory: AnyView? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.stretch = stretch
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 7) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    Text(title)
                        .font(.headline)
                    Spacer()
                    accessory
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity,
               maxHeight: stretch ? .infinity : nil,
               alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }
}

// MARK: - Ring gauge

struct RingGauge: View {
    let value: Double          // 0…1
    let label: String
    let caption: String
    var color: Color = .accentColor
    /// Outer size of the gauge, stroke included.
    var side: CGFloat = 96

    private var lineWidth: CGFloat { max(6, side * 0.1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.55), color],
                                    center: .center,
                                    startAngle: .degrees(-90),
                                    endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: side * 0.19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(caption)
                    .font(.system(size: max(9, side * 0.105)))
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .padding(.horizontal, lineWidth)
        }
        // A stroke straddles its path, so half of it would spill outside the frame and let
        // neighbouring gauges touch; inset by that half instead.
        .padding(lineWidth / 2)
        .frame(width: side, height: side)
    }
}

// MARK: - Flow layout

/// Lays subviews out in a row and wraps to the next line when they no longer fit, centring
/// each line. Used for the gauge strip: a `LazyVGrid` would also wrap, but inside a
/// `ScrollView` it re-runs its visibility bookkeeping on every sample.
struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = layout(subviews: subviews, width: width)
        let height = lines.reduce(0) { $0 + $1.height } +
            lineSpacing * CGFloat(max(lines.count - 1, 0))
        let widest = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let lines = layout(subviews: subviews, width: bounds.width)
        var y = bounds.minY

        for line in lines {
            var x = bounds.minX + (bounds.width - line.width) / 2
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let candidate = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && candidate > width {
                lines.append(current)
                current = Line()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = candidate
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }
}

// MARK: - Metric tile

struct MetricTile: View {
    let title: String
    let value: String
    var detail: String?
    var systemImage: String
    var tint: Color = .accentColor
    /// Fill the height offered by the parent, so tiles sharing a row are the same size even
    /// when only some of them carry a detail line.
    var stretch: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .monospacedDigit()
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity,
               maxHeight: stretch ? .infinity : nil,
               alignment: .topLeading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Labelled progress bar

struct BarRow: View {
    let label: String
    let value: Double          // 0…100
    var trailing: String?
    var tint: Color = .accentColor
    var labelWidth: CGFloat = 78

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(2, geometry.size.width * min(1, max(0, value / 100))))
                }
            }
            .frame(height: 8)

            Text(trailing ?? Format.percent(value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }
}

// MARK: - History chart

/// Sparkline drawn straight into a `Canvas`.
///
/// Swift Charts rebuilds its scales, axes and marks on every data change; with three of these
/// refreshing once a second that alone cost ~10 % CPU. One path fill plus one stroke gives the
/// same picture for a fraction of that.
struct HistoryChart: View {
    let history: History
    var tint: Color = .accentColor
    /// Fixed upper bound (e.g. 100 for percentages); nil scales to the data.
    var maximum: Double?
    var valueFormatter: (Double) -> String = { Format.percent($0) }
    var height: CGFloat = 90

    private var upperBound: Double {
        if let maximum { return maximum }
        // Round the auto-scale up so the axis labels stop jittering on every sample.
        let peak = history.peak
        guard peak > 0 else { return 1 }
        let magnitude = pow(10, (log10(peak)).rounded(.down))
        return (peak / magnitude * 1.25).rounded(.up) * magnitude
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                draw(in: &context, size: size)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                axisLabel(upperBound)
                Spacer(minLength: 0)
                axisLabel(upperBound / 2)
                Spacer(minLength: 0)
                axisLabel(0)
            }
            .frame(width: 42, height: height, alignment: .leading)
        }
        .frame(height: height)
    }

    private func axisLabel(_ value: Double) -> some View {
        Text(valueFormatter(value))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .fixedSize()
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        // Horizontal guides at 0 %, 50 % and 100 % of the scale.
        var guides = Path()
        for fraction in [0.0, 0.5, 1.0] {
            let y = size.height * fraction
            guides.move(to: CGPoint(x: 0, y: y))
            guides.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(guides, with: .color(.gray.opacity(0.22)), lineWidth: 0.5)

        let values = history.values
        guard values.count > 1, size.width > 0 else { return }

        let step = size.width / CGFloat(max(history.limit - 1, 1))
        let scale = size.height / CGFloat(upperBound)
        // Newest sample sits on the right edge and the trace grows leftwards, the way every
        // other system monitor draws it — a half-filled buffer leaves no gap under the cursor.
        func point(_ index: Int) -> CGPoint {
            CGPoint(x: size.width - CGFloat(values.count - 1 - index) * step,
                    y: size.height - min(CGFloat(values[index]) * scale, size.height))
        }

        var line = Path()
        line.move(to: point(0))
        for index in 1..<values.count { line.addLine(to: point(index)) }

        var area = line
        area.addLine(to: CGPoint(x: point(values.count - 1).x, y: size.height))
        area.addLine(to: CGPoint(x: point(0).x, y: size.height))
        area.closeSubpath()

        context.fill(area, with: .linearGradient(
            Gradient(colors: [tint.opacity(0.35), tint.opacity(0.02)]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
        ))
        context.stroke(line, with: .color(tint),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Sensor row

struct SensorRow: View {
    let sensor: Sensor
    let unit: TemperatureUnit

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: sensor.kind.symbol)
                .font(.caption)
                .foregroundStyle(sensor.severityColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(sensor.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(sensor.source.label)
                    if let key = sensor.key { Text(key) }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Text(displayValue)
                .font(.callout.monospacedDigit())
                .foregroundStyle(sensor.kind == .temperature ? sensor.severityColor : .primary)
        }
        .padding(.vertical, 3)
    }

    private var displayValue: String {
        sensor.kind == .temperature ? unit.format(sensor.value) : sensor.formattedValue
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "sensor.tag.radiowaves.forward"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
