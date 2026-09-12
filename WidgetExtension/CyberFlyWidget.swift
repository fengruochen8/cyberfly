import CyberFlyCore
import SwiftUI
import WidgetKit

@main
struct CyberFlyWidgetBundle: WidgetBundle {
    var body: some Widget {
        CyberFlyStateWidget()
    }
}

struct CyberFlyStateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FlyWidgetKind.value, provider: FlyTimelineProvider()) { entry in
            CyberFlyWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [WidgetPalette.backgroundTop, WidgetPalette.backgroundBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("数字果蝇状态")
        .description("查看果蝇的神经动作、内部状态和最近形成的气味记忆。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct FlyWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: FlyStateSnapshot
    let hasData: Bool

    var isStale: Bool {
        snapshot.isStale(relativeTo: date)
    }
}

struct FlyTimelineProvider: TimelineProvider {
    private let store = FlySnapshotStore()

    func placeholder(in context: Context) -> FlyWidgetEntry {
        FlyWidgetEntry(date: Date(), snapshot: .preview(), hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (FlyWidgetEntry) -> Void) {
        let snapshot = context.isPreview ? FlyStateSnapshot.preview() : store.load()
        completion(entry(for: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlyWidgetEntry>) -> Void) {
        let now = Date()
        let entry = entry(for: store.load(), now: now)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(5 * 60))))
    }

    private func entry(for snapshot: FlyStateSnapshot?, now: Date = Date()) -> FlyWidgetEntry {
        FlyWidgetEntry(
            date: now,
            snapshot: snapshot ?? .unavailable(now: now),
            hasData: snapshot != nil
        )
    }
}

struct CyberFlyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FlyWidgetEntry

    var body: some View {
        Group {
            if entry.hasData {
                if family == .systemSmall {
                    compactView
                } else {
                    mediumView
                }
            } else {
                unavailableView
            }
        }
        .widgetURL(URL(string: "cyberfly://status"))
    }

    private var compactView: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            HStack(alignment: .firstTextBaseline) {
                Text(entry.snapshot.emotion.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(statusColor)
                Spacer()
                Text(entry.snapshot.behavior.displayName)
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
            }
            MetricBar(label: "饥饿", value: entry.snapshot.hunger, color: WidgetPalette.hunger)
            MetricBar(label: "好奇", value: entry.snapshot.curiosity, color: WidgetPalette.curiosity)
            MetricBar(label: "快乐", value: entry.snapshot.wellbeing, color: WidgetPalette.wellbeing)
            HStack(spacing: 5) {
                Text(compactFooterText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !entry.isStale {
                    Text(entry.snapshot.sampledAt.formatted(date: .omitted, time: .shortened))
                        .monospacedDigit()
                }
            }
            .font(.caption2)
            .foregroundStyle(entry.isStale ? WidgetPalette.stale : WidgetPalette.secondary)
        }
        .padding(12)
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                header
                Image(systemName: entry.snapshot.behavior.systemImage)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(statusColor)
                Text(entry.snapshot.emotion.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(WidgetPalette.primary)
                Text(entry.snapshot.behavior.displayName)
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondary)
                Spacer(minLength: 0)
                freshness
            }
            .frame(width: 112, alignment: .leading)

            Rectangle()
                .fill(WidgetPalette.separator)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 10) {
                MetricBar(label: "短时愉悦", value: entry.snapshot.valence, color: WidgetPalette.valence)
                MetricBar(label: "长期快乐", value: entry.snapshot.wellbeing, color: WidgetPalette.wellbeing)
                MetricBar(label: "饥饿", value: entry.snapshot.hunger, color: WidgetPalette.hunger)
                MetricBar(label: "好奇", value: entry.snapshot.curiosity, color: WidgetPalette.curiosity)
                Text(entry.snapshot.memorySummary ?? entry.snapshot.reason)
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
                if let actionNeuron = entry.snapshot.selectedActionNeuron {
                    Text("\(actionNeuron) → \(entry.snapshot.behavior.displayName)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(WidgetPalette.live)
                        .lineLimit(1)
                } else if let circuit = entry.snapshot.neuralCircuit {
                    Text(circuit)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(WidgetPalette.live)
                        .lineLimit(1)
                }
            }
        }
        .padding(15)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "ant.fill")
                .foregroundStyle(statusColor)
            Text("数字果蝇")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetPalette.primary)
            Spacer(minLength: 0)
            Circle()
                .fill(entry.isStale ? WidgetPalette.stale : WidgetPalette.live)
                .frame(width: 6, height: 6)
        }
    }

    private var freshness: some View {
        Text(entry.isStale ? "状态可能已过期" : entry.snapshot.sampledAt.formatted(date: .omitted, time: .shortened))
            .font(.caption2)
            .foregroundStyle(entry.isStale ? WidgetPalette.stale : WidgetPalette.secondary)
    }

    private var compactFooterText: String {
        if entry.isStale { return "状态可能已过期" }
        if let memory = entry.snapshot.memorySummary,
           entry.snapshot.memoryConfidence ?? 0 > 0.02 {
            return memory
        }
        return "记忆尚未形成"
    }

    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "ant.fill")
                .font(.title)
                .foregroundStyle(WidgetPalette.stale)
            Text("等待数字果蝇")
                .font(.headline)
                .foregroundStyle(WidgetPalette.primary)
            Text("启动宿主应用后，这里会显示它的当前状态。")
                .font(.caption)
                .foregroundStyle(WidgetPalette.secondary)
        }
        .padding(15)
    }

    private var statusColor: Color {
        switch entry.snapshot.emotion {
        case .happy, .content: WidgetPalette.wellbeing
        case .curious: WidgetPalette.curiosity
        case .hungry: WidgetPalette.hunger
        case .alert: WidgetPalette.alert
        case .distressed: WidgetPalette.distress
        case .tired, .dormant: WidgetPalette.stale
        case .calm: WidgetPalette.live
        }
    }
}

private struct MetricBar: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.secondary)
                Spacer()
                Text(value.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(WidgetPalette.primary)
                    .contentTransition(.numericText(value: value))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(WidgetPalette.track)
                    Capsule()
                        .fill(color)
                        .frame(width: max(2, proxy.size.width * min(max(value, 0), 1)))
                }
            }
            .frame(height: 5)
        }
    }
}

private enum WidgetPalette {
    static let backgroundTop = Color(red: 0.12, green: 0.09, blue: 0.055)
    static let backgroundBottom = Color(red: 0.055, green: 0.075, blue: 0.065)
    static let primary = Color(red: 0.95, green: 0.92, blue: 0.82)
    static let secondary = Color(red: 0.69, green: 0.68, blue: 0.59)
    static let separator = Color(red: 0.31, green: 0.31, blue: 0.25)
    static let track = Color(red: 0.22, green: 0.22, blue: 0.17)
    static let wellbeing = Color(red: 0.43, green: 0.82, blue: 0.42)
    static let valence = Color(red: 0.83, green: 0.72, blue: 0.30)
    static let hunger = Color(red: 0.96, green: 0.51, blue: 0.20)
    static let curiosity = Color(red: 0.31, green: 0.67, blue: 0.95)
    static let alert = Color(red: 0.70, green: 0.48, blue: 0.94)
    static let distress = Color(red: 0.94, green: 0.27, blue: 0.24)
    static let live = Color(red: 0.33, green: 0.84, blue: 0.62)
    static let stale = Color(red: 0.76, green: 0.53, blue: 0.27)
}
