import CyberFlyCore
import Foundation
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
                    WidgetBackdrop()
                }
        }
        .configurationDisplayName("数字果蝇 CNS 监视器")
        .description("以暖黑工业监视面板查看全 CNS 速度、活动和身体状态。")
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
        let snapshot = context.isPreview ? FlyStateSnapshot.preview() : loadedSnapshot()
        completion(entry(for: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlyWidgetEntry>) -> Void) {
        let now = Date()
        completion(
            Timeline(
                entries: [entry(for: loadedSnapshot(), now: now)],
                policy: .after(now.addingTimeInterval(5 * 60))
            )
        )
    }

    private func loadedSnapshot() -> FlyStateSnapshot? {
        try? store.loadReadOnly()
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
        ZStack {
            WidgetGrid()
            if entry.hasData {
                if family == .systemSmall {
                    compactPanel
                } else {
                    monitorPanel
                }
            } else {
                waitingPanel
            }
        }
        .widgetURL(URL(string: "cyberfly://status"))
    }

    private var monitorPanel: some View {
        VStack(spacing: 8) {
            header(compact: false)
            separator
            HStack(spacing: 12) {
                cnsPanel
                Rectangle()
                    .fill(WidgetPalette.border)
                    .frame(width: 1)
                metricColumn
            }
        }
        .padding(13)
    }

    private var compactPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            header(compact: true)
            separator
            Text("CNS.RTF")
                .widgetLabel(size: 8, color: WidgetPalette.ink)
            Text(WidgetFormat.realtime(entry.snapshot.wholeCNSRealTimeFactor ?? 0))
                .font(.system(size: 27, weight: .bold, design: .monospaced))
                .foregroundStyle(WidgetPalette.primary)
                .monospacedDigit()
                .widgetNumericTransition(value: entry.snapshot.wholeCNSRealTimeFactor ?? 0)
            WidgetSegmentBar(
                progress: min((entry.snapshot.wholeCNSRealTimeFactor ?? 0) / 4, 1),
                segments: 10
            )
            HStack(spacing: 10) {
                MiniReadout(code: "HNG", value: WidgetFormat.percent(entry.snapshot.hunger))
                MiniReadout(code: "CUR", value: WidgetFormat.percent(entry.snapshot.curiosity))
                MiniReadout(code: "WEL", value: WidgetFormat.percent(entry.snapshot.wellbeing))
            }
            HStack(spacing: 4) {
                Text(entry.snapshot.selectedActionNeuron ?? "ENG-ACT-IDLE")
                    .widgetLabel(size: 6.5, color: WidgetPalette.muted)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(entry.isStale ? "HOLD" : "LIVE")
                    .widgetLabel(size: 6.5, color: WidgetPalette.ink)
            }
        }
        .padding(12)
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 7) {
            Rectangle()
                .fill(entry.isStale ? WidgetPalette.stale : WidgetPalette.primary)
                .frame(width: 6, height: 6)
            Text(compact ? "CF//FLY" : "CF//CNS.MTR")
                .widgetLabel(size: compact ? 8 : 9, color: WidgetPalette.primary)
            Text(operationalCode)
                .widgetLabel(size: 8, color: entry.isStale ? WidgetPalette.stale : WidgetPalette.ink)
            Spacer(minLength: 4)
            if !compact {
                Text("CNS")
                    .widgetLabel(size: 8, color: WidgetPalette.ink)
                Text(entry.isStale ? "--:--" : entry.snapshot.sampledAt.formatted(date: .omitted, time: .shortened))
                    .widgetLabel(size: 8, color: WidgetPalette.primary)
                    .monospacedDigit()
            }
        }
    }

    private var cnsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CNS.RTF")
                .widgetLabel(size: 8, color: WidgetPalette.ink)
            Text(WidgetFormat.realtime(entry.snapshot.wholeCNSRealTimeFactor ?? 0))
                .font(.system(size: 29, weight: .bold, design: .monospaced))
                .foregroundStyle(WidgetPalette.primary)
                .monospacedDigit()
                .widgetNumericTransition(value: entry.snapshot.wholeCNSRealTimeFactor ?? 0)
            WidgetSegmentBar(
                progress: min((entry.snapshot.wholeCNSRealTimeFactor ?? 0) / 4, 1),
                segments: 10
            )
            Text(
                "ACT \(WidgetFormat.count(entry.snapshot.wholeCNSActiveNeuronCount ?? 0))  "
                    + "SPK \(WidgetFormat.count(entry.snapshot.wholeCNSSpikeCount ?? 0))"
            )
            .widgetLabel(size: 7, color: WidgetPalette.muted)
            .lineLimit(1)
        }
        .frame(width: 112, alignment: .leading)
    }

    private var metricColumn: some View {
        VStack(spacing: 7) {
            WidgetMetricRow(code: "HNG", value: entry.snapshot.hunger)
            WidgetMetricRow(code: "CUR", value: entry.snapshot.curiosity)
            HStack(spacing: 10) {
                WidgetReadout(code: "WEL", value: entry.snapshot.wellbeing)
                WidgetReadout(code: "VAL", value: entry.snapshot.valence)
            }
        }
    }

    private var waitingPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Rectangle().fill(WidgetPalette.stale).frame(width: 6, height: 6)
                Text(family == .systemSmall ? "CF//FLY" : "CF//CNS.MTR")
                    .widgetLabel(size: 9, color: WidgetPalette.primary)
                Spacer()
                Text("OFFLINE").widgetLabel(size: 8, color: WidgetPalette.stale)
            }
            separator
            Text("NO TELEMETRY")
                .font(.system(size: family == .systemSmall ? 21 : 23, weight: .bold, design: .monospaced))
                .foregroundStyle(WidgetPalette.primary)
            Text("START CYBERFLY HOST PROCESS")
                .widgetLabel(size: 8, color: WidgetPalette.muted)
            WidgetSegmentBar(progress: 0, segments: 18)
        }
        .padding(family == .systemSmall ? 12 : 14)
    }

    private var separator: some View {
        Rectangle()
            .fill(WidgetPalette.border)
            .frame(height: 1)
    }

    private var operationalCode: String {
        if entry.isStale { return "HOLD" }
        switch entry.snapshot.emotion {
        case .happy, .content, .calm:
            return "NOMINAL"
        case .curious, .hungry, .alert:
            return "ACTIVE"
        case .tired, .dormant:
            return "REST"
        case .distressed:
            return "FAULT"
        }
    }
}

private struct WidgetMetricRow: View {
    let code: String
    let value: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(code)
                .widgetLabel(size: 8, color: WidgetPalette.ink)
                .frame(width: 28, alignment: .leading)
            WidgetSegmentBar(progress: value, segments: 8)
            Text(WidgetFormat.percent(value))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(WidgetPalette.primary)
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .widgetNumericTransition(value: value)
        }
    }
}

private struct WidgetReadout: View {
    let code: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(code).widgetLabel(size: 7, color: WidgetPalette.ink)
            Text(WidgetFormat.percent(value))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(WidgetPalette.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .widgetNumericTransition(value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MiniReadout: View {
    let code: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(code).widgetLabel(size: 6.5, color: WidgetPalette.ink)
            Text(value)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(WidgetPalette.primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WidgetSegmentBar: View {
    let progress: Double
    let segments: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                Rectangle()
                    .fill(index < activeSegments ? WidgetPalette.primary : WidgetPalette.track)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.4), value: progress)
    }

    private var activeSegments: Int {
        Int((min(max(progress, 0), 1) * Double(segments)).rounded(.up))
    }
}

private struct WidgetGrid: View {
    var body: some View {
        Canvas { context, size in
            for x in stride(from: 0.0, through: size.width, by: 22.0) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(WidgetPalette.grid), lineWidth: 0.55)
            }
            for y in stride(from: 0.0, through: size.height, by: 22.0) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(WidgetPalette.grid), lineWidth: 0.55)
            }
        }
    }
}

private struct WidgetBackdrop: View {
    var body: some View {
        ZStack {
            WidgetPalette.background
            LinearGradient(
                colors: [
                    Color.black.opacity(0.16),
                    WidgetPalette.bronze.opacity(0.28),
                    WidgetPalette.olive.opacity(0.18),
                    WidgetPalette.rust.opacity(0.22)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            RadialGradient(
                colors: [WidgetPalette.olive.opacity(0.18), .clear],
                center: UnitPoint(x: 0.62, y: 0.55),
                startRadius: 0,
                endRadius: 90
            )
            RadialGradient(
                colors: [WidgetPalette.rust.opacity(0.16), .clear],
                center: UnitPoint(x: 0.88, y: 0.82),
                startRadius: 0,
                endRadius: 110
            )
        }
    }
}

private enum WidgetPalette {
    static let background = Color(red: 0.075, green: 0.068, blue: 0.064)
    static let bronze = Color(red: 0.36, green: 0.20, blue: 0.08)
    static let olive = Color(red: 0.24, green: 0.28, blue: 0.14)
    static let rust = Color(red: 0.38, green: 0.13, blue: 0.08)
    static let primary = Color(red: 0.82, green: 0.80, blue: 0.77)
    static let ink = Color(red: 0.76, green: 0.74, blue: 0.71)
    static let muted = Color(red: 0.58, green: 0.56, blue: 0.53)
    static let stale = Color(red: 0.66, green: 0.53, blue: 0.40)
    static let border = Color(red: 0.76, green: 0.74, blue: 0.71).opacity(0.72)
    static let grid = Color(red: 0.68, green: 0.65, blue: 0.59).opacity(0.24)
    static let track = Color(red: 0.33, green: 0.32, blue: 0.30).opacity(0.76)
}

private enum WidgetFormat {
    static func percent(_ value: Double) -> String {
        String(format: "%05.1f%%", min(max(value, 0), 1) * 100)
    }

    static func realtime(_ value: Double) -> String {
        String(format: "%05.2fX", max(value, 0))
    }

    static func count(_ value: Int) -> String {
        switch value {
        case 10_000...:
            return String(format: "%.1fK", Double(value) / 1_000)
        default:
            return String(format: "%04d", max(value, 0))
        }
    }
}

private extension View {
    func widgetLabel(size: CGFloat, color: Color) -> some View {
        font(.system(size: size, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .tracking(0.5)
    }

    func widgetNumericTransition(value: Double) -> some View {
        contentTransition(.numericText(value: value))
            .animation(.easeOut(duration: 0.4), value: value)
    }
}
