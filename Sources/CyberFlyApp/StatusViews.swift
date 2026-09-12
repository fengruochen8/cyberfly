import AppKit
import Combine
import CyberFlyCore
import CyberFlySimulation
import SwiftUI

struct DesktopFlyView: View {
    @ObservedObject var runtime: RuntimeController

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1 / 30,
            paused: runtime.snapshot.wingActivity < 0.06
        )) { context in
            FlyAvatarView(snapshot: runtime.snapshot, date: context.date)
                .frame(width: 34, height: 36)
                .contentShape(Rectangle())
                .onTapGesture { runtime.touchFly() }
                .accessibilityLabel("数字果蝇，\(runtime.snapshot.behavior.displayName)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FoodMarkerView: View {
    @ObservedObject var runtime: RuntimeController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Canvas { context, size in
                let remaining = runtime.food?.remainingPortion ?? 0
                let freshness = runtime.food?.freshness(at: timeline.date) ?? 0
                let odorCue = runtime.food?.odorCue ?? .amber
                let scale = 0.42 + sqrt(remaining) * 0.58
                let fruitSize = CGSize(
                    width: size.width * 0.64 * scale,
                    height: size.height * 0.62 * scale
                )
                let fruitRect = CGRect(
                    x: (size.width - fruitSize.width) / 2,
                    y: size.height * 0.23 + (size.height * 0.62 - fruitSize.height) / 2,
                    width: fruitSize.width,
                    height: fruitSize.height
                )
                let freshColor = odorCue == .amber
                    ? Color.orange
                    : Color(red: 0.78, green: 0.13, blue: 0.32)
                let fruitColor = odorCue == .amber
                    ? Color(red: 0.34 + freshness * 0.38, green: 0.08 + freshness * 0.08, blue: 0.05)
                    : Color(red: 0.28 + freshness * 0.34, green: 0.05, blue: 0.12 + freshness * 0.16)
                context.fill(
                    Path(ellipseIn: fruitRect),
                    with: .radialGradient(
                        Gradient(colors: [freshColor.opacity(0.35 + freshness * 0.65), fruitColor]),
                        center: CGPoint(x: fruitRect.midX - fruitRect.width * 0.18, y: fruitRect.midY - fruitRect.height * 0.2),
                        startRadius: 1,
                        endRadius: fruitRect.width * 0.65
                    )
                )

                if freshness < 0.85 {
                    let decay = 1 - freshness
                    for offset in [CGPoint(x: -0.16, y: -0.08), CGPoint(x: 0.13, y: 0.12), CGPoint(x: 0.05, y: -0.2)] {
                        let spotSize = max(2, fruitRect.width * 0.08 * decay)
                        context.fill(
                            Path(ellipseIn: CGRect(
                                x: fruitRect.midX + fruitRect.width * offset.x - spotSize / 2,
                                y: fruitRect.midY + fruitRect.height * offset.y - spotSize / 2,
                                width: spotSize,
                                height: spotSize
                            )),
                            with: .color(.black.opacity(decay * 0.55))
                        )
                    }
                }

                var stem = Path()
                stem.move(to: CGPoint(x: fruitRect.midX, y: fruitRect.minY + 2))
                stem.addCurve(
                    to: CGPoint(x: fruitRect.midX + size.width * 0.16, y: size.height * 0.13),
                    control1: CGPoint(x: fruitRect.midX, y: size.height * 0.16),
                    control2: CGPoint(x: fruitRect.midX + size.width * 0.08, y: size.height * 0.12)
                )
                context.stroke(stem, with: .color(.brown), lineWidth: 2.4)
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: fruitRect.midX + size.width * 0.06,
                        y: size.height * 0.08,
                        width: size.width * 0.28,
                        height: size.height * 0.15
                    )),
                    with: .color(.green.opacity(0.35 + freshness * 0.65))
                )
            }
            .accessibilityLabel(foodAccessibilityLabel(at: timeline.date))
        }
        .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
    }

    private func foodAccessibilityLabel(at date: Date) -> String {
        guard let food = runtime.food else { return "没有水果" }
        return "\(food.odorCue.displayName)水果，\(food.phase(at: date).displayName)，剩余 \(Int((food.remainingPortion * 100).rounded()))%"
    }
}

private struct FlyAvatarView: View {
    let snapshot: FlyStateSnapshot
    let date: Date

    var body: some View {
        Canvas { context, size in
            let referenceSize = CGSize(width: 120, height: 130)
            context.scaleBy(
                x: size.width / referenceSize.width,
                y: size.height / referenceSize.height
            )

            let center = CGPoint(x: referenceSize.width / 2, y: referenceSize.height / 2)
            context.translateBy(x: center.x, y: center.y)
            // The reference character faces upward. This rotation aligns that
            // direction with the simulation's screen-space movement heading.
            context.rotate(by: .radians(.pi / 2 - snapshot.headingRadians))
            context.translateBy(x: -center.x, y: -center.y)

            let phase = sin(
                date.timeIntervalSinceReferenceDate
                    * (13 + snapshot.wingActivity * 105)
            )
            let wingLift = CGFloat(phase * snapshot.wingActivity * 7)
            let outline = Color(red: 0.035, green: 0.035, blue: 0.03)
            let outlineStyle = StrokeStyle(
                lineWidth: 4.6,
                lineCap: .round,
                lineJoin: .round
            )
            let detailStyle = StrokeStyle(
                lineWidth: 2.7,
                lineCap: .round,
                lineJoin: .round
            )

            let legs = legPath(for: snapshot.behavior, phase: phase)
            context.stroke(legs, with: .color(outline), style: StrokeStyle(
                lineWidth: 3.6,
                lineCap: .round,
                lineJoin: .round
            ))

            for wing in wingPaths(lift: wingLift) {
                context.fill(
                    wing,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.white.opacity(0.92),
                            Color(red: 0.68, green: 0.69, blue: 0.70).opacity(0.94)
                        ]),
                        startPoint: CGPoint(x: 60, y: 48),
                        endPoint: CGPoint(x: 60, y: 96)
                    )
                )
                context.stroke(wing, with: .color(outline), style: outlineStyle)
            }

            let abdomen = abdomenPath()
            context.fill(
                abdomen,
                with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 0.31, green: 0.30, blue: 0.30),
                        Color(red: 0.18, green: 0.17, blue: 0.17)
                    ]),
                    center: CGPoint(x: 48, y: 75),
                    startRadius: 3,
                    endRadius: 58
                )
            )
            context.stroke(abdomen, with: .color(outline), style: outlineStyle)

            let abdomenDetails = abdomenDetailPath()
            context.stroke(
                abdomenDetails,
                with: .color(outline.opacity(0.92)),
                style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
            )

            let thorax = thoraxPath()
            context.fill(
                thorax,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.02, green: 0.72, blue: 0.53),
                        Color(red: 0.0, green: 0.48, blue: 0.38)
                    ]),
                    startPoint: CGPoint(x: 42, y: 24),
                    endPoint: CGPoint(x: 72, y: 88)
                )
            )
            context.stroke(thorax, with: .color(outline), style: outlineStyle)

            let proboscis = proboscisPath(for: snapshot.behavior, phase: phase)
            context.fill(
                proboscis,
                with: .color(Color(red: 0.0, green: 0.63, blue: 0.47))
            )
            context.stroke(proboscis, with: .color(outline), style: outlineStyle)

            let antenna = antennaPath()
            context.stroke(
                antenna,
                with: .color(outline),
                style: StrokeStyle(lineWidth: 4.2, lineCap: .round, lineJoin: .round)
            )

            let leftEye = CGRect(x: 8, y: 18, width: 54, height: 51)
            let rightEye = CGRect(x: 57, y: 20, width: 55, height: 52)
            for eye in [leftEye, rightEye] {
                let eyePath = Path(ellipseIn: eye)
                context.fill(
                    eyePath,
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 1.0, green: 0.86, blue: 0.18),
                            Color(red: 1.0, green: 0.57, blue: 0.05)
                        ]),
                        center: CGPoint(x: eye.minX + eye.width * 0.35, y: eye.minY + eye.height * 0.28),
                        startRadius: 2,
                        endRadius: eye.width * 0.78
                    )
                )
                context.stroke(eyePath, with: .color(outline), style: outlineStyle)
                context.stroke(
                    eyeGridPath(in: eye),
                    with: .color(Color(red: 0.77, green: 0.36, blue: 0.11).opacity(0.72)),
                    style: detailStyle
                )
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: eye.minX + eye.width * 0.16,
                        y: eye.minY + eye.height * 0.15,
                        width: eye.width * 0.25,
                        height: eye.height * 0.17
                    )),
                    with: .color(Color.yellow.opacity(0.72))
                )
            }

            if snapshot.behavior == .resting || snapshot.behavior == .torpor {
                context.stroke(
                    sleepyEyePath(leftEye: leftEye, rightEye: rightEye),
                    with: .color(outline),
                    style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                )
            }
        }
        .opacity(snapshot.lifeState == .active ? 1 : 0.58)
        .shadow(color: .black.opacity(0.28), radius: 3, y: 3)
    }

    private func wingPaths(lift: CGFloat) -> [Path] {
        var leftUpper = Path()
        leftUpper.move(to: CGPoint(x: 29, y: 59))
        leftUpper.addCurve(
            to: CGPoint(x: 27, y: 78 + lift),
            control1: CGPoint(x: 10, y: 49 + lift),
            control2: CGPoint(x: 4, y: 68 + lift)
        )
        leftUpper.addCurve(
            to: CGPoint(x: 34, y: 69),
            control1: CGPoint(x: 22, y: 82 + lift),
            control2: CGPoint(x: 30, y: 77)
        )
        leftUpper.closeSubpath()

        var leftLower = Path()
        leftLower.move(to: CGPoint(x: 30, y: 70))
        leftLower.addCurve(
            to: CGPoint(x: 29, y: 94 - lift * 0.45),
            control1: CGPoint(x: 9, y: 68 - lift * 0.45),
            control2: CGPoint(x: 8, y: 90 - lift * 0.45)
        )
        leftLower.addCurve(
            to: CGPoint(x: 38, y: 79),
            control1: CGPoint(x: 36, y: 96 - lift * 0.45),
            control2: CGPoint(x: 40, y: 87)
        )
        leftLower.closeSubpath()

        var rightUpper = Path()
        rightUpper.move(to: CGPoint(x: 91, y: 59))
        rightUpper.addCurve(
            to: CGPoint(x: 94, y: 78 - lift),
            control1: CGPoint(x: 110, y: 49 - lift),
            control2: CGPoint(x: 118, y: 68 - lift)
        )
        rightUpper.addCurve(
            to: CGPoint(x: 86, y: 69),
            control1: CGPoint(x: 99, y: 82 - lift),
            control2: CGPoint(x: 90, y: 77)
        )
        rightUpper.closeSubpath()

        var rightLower = Path()
        rightLower.move(to: CGPoint(x: 90, y: 70))
        rightLower.addCurve(
            to: CGPoint(x: 91, y: 94 + lift * 0.45),
            control1: CGPoint(x: 111, y: 68 + lift * 0.45),
            control2: CGPoint(x: 114, y: 90 + lift * 0.45)
        )
        rightLower.addCurve(
            to: CGPoint(x: 82, y: 79),
            control1: CGPoint(x: 84, y: 96 + lift * 0.45),
            control2: CGPoint(x: 80, y: 87)
        )
        rightLower.closeSubpath()

        return [leftUpper, leftLower, rightUpper, rightLower]
    }

    private func abdomenPath() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 27, y: 64))
        path.addCurve(
            to: CGPoint(x: 94, y: 66),
            control1: CGPoint(x: 44, y: 56),
            control2: CGPoint(x: 78, y: 57)
        )
        path.addCurve(
            to: CGPoint(x: 91, y: 108),
            control1: CGPoint(x: 103, y: 80),
            control2: CGPoint(x: 102, y: 99)
        )
        path.addCurve(
            to: CGPoint(x: 61, y: 121),
            control1: CGPoint(x: 84, y: 118),
            control2: CGPoint(x: 72, y: 122)
        )
        path.addCurve(
            to: CGPoint(x: 29, y: 107),
            control1: CGPoint(x: 47, y: 123),
            control2: CGPoint(x: 34, y: 118)
        )
        path.addCurve(
            to: CGPoint(x: 27, y: 64),
            control1: CGPoint(x: 18, y: 96),
            control2: CGPoint(x: 18, y: 76)
        )
        path.closeSubpath()
        return path
    }

    private func abdomenDetailPath() -> Path {
        var path = Path()
        for x in [38.0, 51.0, 66.0, 80.0] {
            path.move(to: CGPoint(x: x, y: 108))
            path.addCurve(
                to: CGPoint(x: x + (x < 60 ? -4 : 4), y: 123),
                control1: CGPoint(x: x - 1, y: 114),
                control2: CGPoint(x: x + (x < 60 ? -3 : 3), y: 119)
            )
        }
        return path
    }

    private func thoraxPath() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 22, y: 31))
        path.addCurve(
            to: CGPoint(x: 98, y: 33),
            control1: CGPoint(x: 40, y: 17),
            control2: CGPoint(x: 82, y: 18)
        )
        path.addCurve(
            to: CGPoint(x: 96, y: 72),
            control1: CGPoint(x: 106, y: 43),
            control2: CGPoint(x: 105, y: 62)
        )
        path.addCurve(
            to: CGPoint(x: 60, y: 86),
            control1: CGPoint(x: 87, y: 83),
            control2: CGPoint(x: 75, y: 86)
        )
        path.addCurve(
            to: CGPoint(x: 23, y: 71),
            control1: CGPoint(x: 43, y: 86),
            control2: CGPoint(x: 29, y: 81)
        )
        path.addCurve(
            to: CGPoint(x: 22, y: 31),
            control1: CGPoint(x: 14, y: 58),
            control2: CGPoint(x: 14, y: 42)
        )
        path.closeSubpath()
        return path
    }

    private func proboscisPath(for behavior: FlyBehavior, phase: Double) -> Path {
        let groomingLift = behavior == .groomingHead ? CGFloat(phase * 4) : 0
        var path = Path()
        path.move(to: CGPoint(x: 50, y: 53))
        path.addCurve(
            to: CGPoint(x: 42, y: 91 + groomingLift),
            control1: CGPoint(x: 50, y: 66),
            control2: CGPoint(x: 43, y: 80 + groomingLift)
        )
        path.addCurve(
            to: CGPoint(x: 35, y: 106 + groomingLift),
            control1: CGPoint(x: 40, y: 97 + groomingLift),
            control2: CGPoint(x: 37, y: 101 + groomingLift)
        )
        path.addCurve(
            to: CGPoint(x: 24, y: 105 + groomingLift),
            control1: CGPoint(x: 31, y: 110 + groomingLift),
            control2: CGPoint(x: 28, y: 107 + groomingLift)
        )
        path.addCurve(
            to: CGPoint(x: 19, y: 97 + groomingLift),
            control1: CGPoint(x: 18, y: 108 + groomingLift),
            control2: CGPoint(x: 14, y: 102 + groomingLift)
        )
        path.addCurve(
            to: CGPoint(x: 30, y: 91 + groomingLift),
            control1: CGPoint(x: 20, y: 90 + groomingLift),
            control2: CGPoint(x: 25, y: 89 + groomingLift)
        )
        path.addCurve(
            to: CGPoint(x: 42, y: 51),
            control1: CGPoint(x: 34, y: 78),
            control2: CGPoint(x: 38, y: 63)
        )
        path.closeSubpath()
        return path
    }

    private func antennaPath() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 63, y: 22))
        path.addCurve(
            to: CGPoint(x: 72, y: 3),
            control1: CGPoint(x: 62, y: 14),
            control2: CGPoint(x: 76, y: 13)
        )
        path.addCurve(
            to: CGPoint(x: 70, y: -4),
            control1: CGPoint(x: 73, y: 0),
            control2: CGPoint(x: 72, y: -2)
        )
        return path
    }

    private func eyeGridPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.37, y: rect.minY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.29, y: rect.minY + rect.height * 0.82))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.70, y: rect.minY + rect.height * 0.21))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.63, y: rect.minY + rect.height * 0.84))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.47))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.minY + rect.height * 0.68))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.76, y: rect.minY + rect.height * 0.72))
        return path
    }

    private func legPath(for behavior: FlyBehavior, phase: Double) -> Path {
        let groom = behavior == .groomingHead || behavior == .groomingWings
        let lift = groom ? CGFloat(phase * 5) : 0
        var path = Path()
        let legs: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: 33, y: 90), CGPoint(x: 18, y: 103 - lift), CGPoint(x: 10, y: 111 - lift)),
            (CGPoint(x: 38, y: 101), CGPoint(x: 25, y: 118), CGPoint(x: 24, y: 130)),
            (CGPoint(x: 49, y: 108), CGPoint(x: 43, y: 124), CGPoint(x: 39, y: 132)),
            (CGPoint(x: 71, y: 108), CGPoint(x: 77, y: 124), CGPoint(x: 82, y: 132)),
            (CGPoint(x: 82, y: 101), CGPoint(x: 95, y: 118), CGPoint(x: 102, y: 123)),
            (CGPoint(x: 88, y: 89), CGPoint(x: 104, y: 101 + lift), CGPoint(x: 113, y: 105 + lift))
        ]
        for leg in legs {
            path.move(to: leg.0)
            path.addCurve(to: leg.2, control1: leg.1, control2: leg.1)
        }
        return path
    }

    private func sleepyEyePath(leftEye: CGRect, rightEye: CGRect) -> Path {
        var path = Path()
        for eye in [leftEye, rightEye] {
            path.move(to: CGPoint(x: eye.minX + eye.width * 0.23, y: eye.midY))
            path.addCurve(
                to: CGPoint(x: eye.maxX - eye.width * 0.20, y: eye.midY + 1),
                control1: CGPoint(x: eye.midX - 7, y: eye.midY + 6),
                control2: CGPoint(x: eye.midX + 7, y: eye.midY + 6)
            )
        }
        return path
    }
}

struct StatusDashboardView: View {
    @ObservedObject var runtime: RuntimeController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: runtime.snapshot.behavior.systemImage)
                    .font(.system(size: 30))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(runtime.snapshot.emotion.displayName)
                        .font(.title2.weight(.semibold))
                    Text(runtime.snapshot.behavior.displayName)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(runtime.snapshot.lifeState.displayName)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.13), in: Capsule())
            }

            Text(runtime.snapshot.reason)
                .font(.body)

            if let controller = runtime.snapshot.controllerCircuit,
               let actionNeuron = runtime.snapshot.selectedActionNeuron {
                VStack(alignment: .leading, spacing: 5) {
                    Label("全动作神经控制", systemImage: "brain")
                        .font(.caption.weight(.semibold))
                    Text("\(actionNeuron) → \(runtime.snapshot.behavior.displayName)")
                        .font(.subheadline.weight(.medium))
                    HStack {
                        Text("\(controller) · \(runtime.snapshot.activeControllerNeuronCount ?? 0)/\(runtime.snapshot.controllerNeuronCount ?? 0) 活跃")
                        Spacer()
                        if let confidence = runtime.snapshot.actionConfidence {
                            Text("竞争差 \(confidence.formatted(.percent.precision(.fractionLength(0))))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Text("动作与下降运动层：\(runtime.snapshot.controllerProvenance ?? "fitted/assumed")；并非 MaleCNS 直接观测。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }

            if let circuit = runtime.snapshot.neuralCircuit,
               let activeCount = runtime.snapshot.activeNeuronCount {
                Label(
                    "\(circuit) · \(activeCount) 个神经元刚刚放电",
                    systemImage: "waveform.path.ecg"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            if let learningCircuit = runtime.snapshot.learningCircuit {
                VStack(alignment: .leading, spacing: 6) {
                    Label("学习与记忆", systemImage: "brain.head.profile")
                        .font(.caption.weight(.semibold))
                    Text(runtime.snapshot.memorySummary ?? "尚未形成气味联想")
                        .font(.subheadline)
                    HStack {
                        Text("\(learningCircuit) · \(runtime.snapshot.activeKenyonCellCount ?? 0) 个 KC 活跃")
                        Spacer()
                        if let confidence = runtime.snapshot.memoryConfidence {
                            Text("记忆 \(confidence.formatted(.percent.precision(.fractionLength(0))))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    if let learnedValence = runtime.snapshot.learnedValence {
                        LearningBalanceBar(value: learnedValence)
                    }
                }
                .padding(10)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            VStack(spacing: 12) {
                StateMeter(title: "短时愉悦", value: runtime.snapshot.valence, color: .green)
                StateMeter(title: "长期满足", value: runtime.snapshot.wellbeing, color: .mint)
                StateMeter(title: "饥饿", value: runtime.snapshot.hunger, color: .orange)
                StateMeter(title: "好奇", value: runtime.snapshot.curiosity, color: .blue)
                StateMeter(title: "警觉", value: runtime.snapshot.arousal, color: .purple)
                StateMeter(title: "梳理需求", value: runtime.snapshot.groomingNeed, color: .brown)
            }

            HStack {
                Button("放置琥珀果香") { runtime.placeFood(odorCue: .amber) }
                Button("放置莓红果香") { runtime.placeFood(odorCue: .berry) }
                if runtime.food != nil {
                    Button("收走水果") { runtime.removeFood() }
                }
            }
            HStack {
                Button("轻触") { runtime.touchFly() }
                Button("增加灰尘") { runtime.addDust() }
                Spacer()
                Button(runtime.isPaused ? "继续" : "暂停") { runtime.togglePause() }
            }

            if let food = runtime.food {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    HStack(spacing: 8) {
                        Label("\(food.odorCue.displayName) · \(food.phase(at: timeline.date).displayName)", systemImage: "apple.logo")
                        ProgressView(value: food.remainingPortion)
                            .frame(maxWidth: 110)
                        Text("剩余 \(food.remainingPortion.formatted(.percent.precision(.fractionLength(0))))")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Divider()
            Text("所有动作、速度、转向、振翅、进食和梳理门控均来自神经控制器输出。身体层只更新能量、疲劳、碰撞和位置。当前阶段：\(runtime.snapshot.modelFidelity.displayName)。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
        }
        .frame(minWidth: 430, idealWidth: 460)
    }

    private var accent: Color {
        switch runtime.snapshot.emotion {
        case .happy, .content: .green
        case .curious: .blue
        case .alert: .purple
        case .hungry: .orange
        case .tired, .dormant: .gray
        case .distressed: .red
        case .calm: .teal
        }
    }
}

private struct StateMeter: View {
    let title: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 72, alignment: .leading)
            ProgressView(value: value)
                .tint(color)
            Text(value.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
        }
    }
}

private struct LearningBalanceBar: View {
    let value: Double

    var body: some View {
        HStack(spacing: 7) {
            Text("回避")
            GeometryReader { proxy in
                ZStack {
                    Capsule().fill(.secondary.opacity(0.13))
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 1)
                    Capsule()
                        .fill(value >= 0 ? Color.green : Color.red)
                        .frame(width: max(2, proxy.size.width * abs(value) / 2))
                        .offset(x: proxy.size.width * value / 4)
                }
            }
            .frame(height: 6)
            Text("趋近")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

@MainActor
final class StatusMenuController: NSObject, NSWindowDelegate {
    private let runtime: RuntimeController
    private let flyPanelController: FlyPanelController
    private let statusItem: NSStatusItem
    private var snapshotSubscription: AnyCancellable?
    private var pauseSubscription: AnyCancellable?
    private var dashboardWindow: NSWindow?

    private let moodItem = NSMenuItem(title: "情绪：--", action: nil, keyEquivalent: "")
    private let behaviorItem = NSMenuItem(title: "动作：--", action: nil, keyEquivalent: "")
    private let hungerItem = NSMenuItem(title: "饥饿：--", action: nil, keyEquivalent: "")
    private let curiosityItem = NSMenuItem(title: "好奇：--", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "暂停", action: #selector(togglePause), keyEquivalent: "p")
    private let visibilityItem = NSMenuItem(title: "隐藏果蝇", action: #selector(toggleFlyVisibility), keyEquivalent: "h")

    init(runtime: RuntimeController, flyPanelController: FlyPanelController) {
        self.runtime = runtime
        self.flyPanelController = flyPanelController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "ant.fill", accessibilityDescription: "数字果蝇")
        }
        statusItem.menu = makeMenu()
        snapshotSubscription = runtime.$snapshot.sink { [weak self] snapshot in
            self?.update(snapshot: snapshot)
        }
        pauseSubscription = runtime.$isPaused.sink { [weak self] paused in
            self?.pauseItem.title = paused ? "继续" : "暂停"
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        [moodItem, behaviorItem, hungerItem, curiosityItem].forEach {
            $0.isEnabled = false
            menu.addItem($0)
        }
        menu.addItem(.separator())
        menu.addItem(item("打开实时状态", action: #selector(openDashboard), key: "s"))
        menu.addItem(item("放置琥珀果香", action: #selector(placeAmberFood), key: "f"))
        menu.addItem(item("放置莓红果香", action: #selector(placeBerryFood), key: "b"))
        menu.addItem(item("轻触果蝇", action: #selector(touchFly), key: "t"))
        menu.addItem(item("增加灰尘", action: #selector(addDust), key: "d"))
        menu.addItem(.separator())
        pauseItem.target = self
        visibilityItem.target = self
        menu.addItem(pauseItem)
        menu.addItem(visibilityItem)
        menu.addItem(item("救活果蝇", action: #selector(revive), key: "r"))
        menu.addItem(.separator())
        menu.addItem(item("退出数字果蝇", action: #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func update(snapshot: FlyStateSnapshot) {
        moodItem.title = "情绪：\(snapshot.emotion.displayName)"
        behaviorItem.title = "动作：\(snapshot.behavior.displayName)"
        hungerItem.title = "饥饿：\(Int((snapshot.hunger * 100).rounded()))%"
        curiosityItem.title = "好奇：\(Int((snapshot.curiosity * 100).rounded()))%"
    }

    func showDashboard() {
        if dashboardWindow == nil {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 500, height: 720),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "数字果蝇 · 实时状态"
            window.contentView = NSHostingView(rootView: StatusDashboardView(runtime: runtime))
            window.isReleasedWhenClosed = false
            window.delegate = self
            dashboardWindow = window
        }
        dashboardWindow?.center()
        dashboardWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func openDashboard() {
        showDashboard()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === dashboardWindow else { return }
        dashboardWindow?.contentView = nil
        dashboardWindow = nil
    }

    @objc private func placeAmberFood() { runtime.placeFood(odorCue: .amber) }
    @objc private func placeBerryFood() { runtime.placeFood(odorCue: .berry) }
    @objc private func touchFly() { runtime.touchFly() }
    @objc private func addDust() { runtime.addDust() }
    @objc private func togglePause() { runtime.togglePause() }
    @objc private func revive() { runtime.revive() }

    @objc private func toggleFlyVisibility() {
        flyPanelController.toggleVisibility()
        visibilityItem.title = flyPanelController.isVisible ? "隐藏果蝇" : "显示果蝇"
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
