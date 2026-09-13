import AppKit
import Charts
import Combine
import CyberFlyCore
import CyberFlySimulation
import SwiftUI
import UniformTypeIdentifiers

enum NeuralLabPage: String, CaseIterable, Identifiable {
    case live
    case selfModel
    case cognitive
    case neurons
    case experiment
    case results

    var id: Self { self }

    var title: String {
        switch self {
        case .live: "实时脑窗"
        case .selfModel: "自我模型"
        case .cognitive: "认知进阶"
        case .neurons: "神经元浏览器"
        case .experiment: "实验控制台"
        case .results: "对照结果"
        }
    }

    var subtitle: String {
        switch self {
        case .live: "观察感觉到行动的闭环"
        case .selfModel: "检验身体、能动性与不确定度"
        case .cognitive: "反事实、长期目标与他者模型"
        case .neurons: "查询与检查 MaleCNS 节点"
        case .experiment: "构造可重复的因果干预"
        case .results: "比较对照组与干预组"
        }
    }

    var systemImage: String {
        switch self {
        case .live: "waveform.path.ecg"
        case .selfModel: "person.crop.circle.badge.questionmark"
        case .cognitive: "point.3.connected.trianglepath.dotted"
        case .neurons: "point.3.filled.connected.trianglepath.dotted"
        case .experiment: "slider.horizontal.3"
        case .results: "chart.xyaxis.line"
        }
    }
}

enum NeuralRoleFilter: String, CaseIterable, Identifiable {
    case all
    case sensory
    case visual
    case olfactory
    case gustatory
    case mechanosensory
    case mushroomBody
    case centralComplex
    case ascending
    case descending
    case motor
    case dopaminergic
    case neurosecretory
    case sexSpecific

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部角色"
        case .sensory: "感觉"
        case .visual: "视觉"
        case .olfactory: "嗅觉"
        case .gustatory: "味觉"
        case .mechanosensory: "机械感觉"
        case .mushroomBody: "蘑菇体"
        case .centralComplex: "中央复合体"
        case .ascending: "上行"
        case .descending: "下行"
        case .motor: "运动"
        case .dopaminergic: "多巴胺"
        case .neurosecretory: "神经分泌"
        case .sexSpecific: "性别相关"
        }
    }

    var role: FullCNSNodeRole? {
        switch self {
        case .all: nil
        case .sensory: .sensory
        case .visual: .visual
        case .olfactory: .olfactory
        case .gustatory: .gustatory
        case .mechanosensory: .mechanosensory
        case .mushroomBody: .mushroomBody
        case .centralComplex: .centralComplex
        case .ascending: .ascending
        case .descending: .descending
        case .motor: .motor
        case .dopaminergic: .dopaminergic
        case .neurosecretory: .neurosecretory
        case .sexSpecific: .sexSpecific
        }
    }
}

enum NeuralTransmitterFilter: String, CaseIterable, Identifiable {
    case all
    case acetylcholine
    case gaba
    case glutamate
    case dopamine
    case serotonin
    case octopamine
    case histamine
    case unclear

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部递质"
        case .acetylcholine: "乙酰胆碱"
        case .gaba: "GABA"
        case .glutamate: "谷氨酸"
        case .dopamine: "多巴胺"
        case .serotonin: "血清素"
        case .octopamine: "章鱼胺"
        case .histamine: "组胺"
        case .unclear: "未明确"
        }
    }

    var transmitter: FullCNSNeurotransmitter? {
        switch self {
        case .all: nil
        case .acetylcholine: .acetylcholine
        case .gaba: .gaba
        case .glutamate: .glutamate
        case .dopamine: .dopamine
        case .serotonin: .serotonin
        case .octopamine: .octopamine
        case .histamine: .histamine
        case .unclear: .unclear
        }
    }
}

enum NeuralHemisphereFilter: String, CaseIterable, Identifiable {
    case all
    case left
    case right
    case midline
    case unknown

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部侧别"
        case .left: "左侧"
        case .right: "右侧"
        case .midline: "中线"
        case .unknown: "未标注"
        }
    }

    var hemisphere: FullCNSHemisphere? {
        switch self {
        case .all: nil
        case .left: .left
        case .right: .right
        case .midline: .midline
        case .unknown: .unknown
        }
    }
}

struct NeuralLiveTracePoint: Identifiable {
    let id: Int
    let date: Date
    let sensory: Double
    let central: Double
    let descending: Double
    let motor: Double
    let dopamine: Double
}

@MainActor
final class NeuralLabController: ObservableObject {
    @Published var selectedPage: NeuralLabPage = .live
    @Published private(set) var snapshot: FlyStateSnapshot
    @Published private(set) var liveTrace: [NeuralLiveTracePoint] = []

    @Published var searchText = ""
    @Published var roleFilter: NeuralRoleFilter = .descending
    @Published var transmitterFilter: NeuralTransmitterFilter = .all
    @Published var hemisphereFilter: NeuralHemisphereFilter = .all
    @Published private(set) var neuronResults: [FullCNSNeuronObservation] = []
    @Published var selectedBodyID: UInt64?
    @Published private(set) var selectedNeuron: FullCNSNeuronObservation?

    @Published var experimentName = "DNg13 视觉转向"
    @Published var targetBodyIDs = "11074, 512006"
    @Published var interventionMode: FullCNSInterventionMode = .silence
    @Published var stimulationAmplitude = 1.0
    @Published var leftVisualMotion = 1.0
    @Published var rightVisualMotion = 0.05
    @Published var odor = 0.0
    @Published var taste = 0.0
    @Published var touch = 0.2
    @Published var proprioception = 0.0
    @Published var hunger = 0.0
    @Published var reward = 0.0
    @Published var punishment = 0.0
    @Published var duration = 0.8
    @Published private(set) var isRunningExperiment = false
    @Published private(set) var experimentProgressText = "准备就绪"
    @Published private(set) var experimentResult: FullCNSExperimentResult?
    @Published var experimentError: String?

    let manifest: FullCNSManifest?

    private let runtime: RuntimeController
    private var snapshotSubscription: AnyCancellable?
    private var traceSequence = 0
    private var lastTraceAt = Date.distantPast

    init(runtime: RuntimeController) {
        self.runtime = runtime
        self.snapshot = runtime.snapshot
        self.manifest = runtime.fullCNSManifest
        selectedBodyID = 11_074
        selectedNeuron = runtime.inspectFullCNSNeuron(bodyID: 11_074)
        snapshotSubscription = runtime.$snapshot.sink { [weak self] snapshot in
            self?.receive(snapshot)
        }
        refreshNeuronResults()
    }

    func selectPage(_ page: NeuralLabPage) {
        selectedPage = page
    }

    func displaceFlyExternally() {
        runtime.displaceFlyExternally()
    }

    func maskSenses() {
        runtime.maskSenses()
    }

    func reverseSteering() {
        runtime.reverseSteering()
    }

    func applyHiddenWind() {
        runtime.applyHiddenWind()
    }

    func triggerGoalConflict() {
        runtime.triggerGoalConflict()
    }

    func introduceOtherAgent(contingent: Bool = true) {
        runtime.introduceOtherAgent(contingent: contingent)
    }

    func refreshNeuronResults() {
        let query = FullCNSNeuronQuery(
            bodyIDText: searchText,
            role: roleFilter.role,
            transmitter: transmitterFilter.transmitter,
            hemisphere: hemisphereFilter.hemisphere,
            limit: 120
        )
        neuronResults = runtime.inspectFullCNSNeurons(matching: query)
        if let selectedBodyID {
            selectedNeuron = runtime.inspectFullCNSNeuron(bodyID: selectedBodyID)
        } else if let first = neuronResults.first {
            selectNeuron(first)
        }
    }

    func selectNeuron(_ neuron: FullCNSNeuronObservation) {
        selectedBodyID = neuron.bodyID
        selectedNeuron = neuron
    }

    func useSelectedNeuronAsTarget() {
        guard let selectedNeuron else { return }
        targetBodyIDs = String(selectedNeuron.bodyID)
        experimentName = "body \(selectedNeuron.bodyID) 因果干预"
        selectedPage = .experiment
    }

    func loadDNg13Preset() {
        experimentName = "DNg13 视觉转向"
        targetBodyIDs = "11074, 512006"
        interventionMode = .silence
        stimulationAmplitude = 1
        leftVisualMotion = 1
        rightVisualMotion = 0.05
        odor = 0
        taste = 0
        touch = 0.2
        proprioception = 0
        hunger = 0
        reward = 0
        punishment = 0
        duration = 0.8
        experimentError = nil
    }

    func runExperiment() {
        guard !isRunningExperiment else { return }
        let bodyIDs = parseBodyIDs(targetBodyIDs)
        guard !bodyIDs.isEmpty else {
            experimentError = "请输入至少一个有效的 MaleCNS body ID。"
            return
        }
        let isDNg13Gate = interventionMode == .silence
            && Set(bodyIDs) == Set([UInt64(11_074), UInt64(512_006)])
        let definition = FullCNSExperimentDefinition(
            name: experimentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "未命名实验"
                : experimentName,
            targetBodyIDs: bodyIDs,
            intervention: interventionMode,
            stimulationAmplitude: stimulationAmplitude,
            input: FullCNSSensoryInput(
                leftVisualMotion: leftVisualMotion,
                rightVisualMotion: rightVisualMotion,
                odor: odor,
                taste: taste,
                touch: touch,
                proprioception: proprioception,
                hunger: hunger,
                reward: reward,
                punishment: punishment
            ),
            duration: duration,
            sampleInterval: 0.1,
            expectation: isDNg13Gate ? .eliminateVisualTurnBias : .observeDifference
        )

        isRunningExperiment = true
        experimentError = nil
        experimentProgressText = "正在创建独立的对照组与干预组…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let graph = try FullCNSGraph.bundled()
                    return try FullCNSExperimentRunner.run(
                        graph: graph,
                        definition: definition
                    )
                }.value
                experimentResult = result
                experimentProgressText = "实验完成 · \(result.samples.count) 个时间点"
                selectedPage = .results
            } catch {
                experimentError = error.localizedDescription
                experimentProgressText = "实验未完成"
            }
            isRunningExperiment = false
        }
    }

    func exportExperimentResult() {
        guard let experimentResult else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "CyberFly-\(safeFilename(experimentResult.definition.name)).json"
        panel.title = "导出数字果蝇实验"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(experimentResult).write(to: url, options: .atomic)
            experimentProgressText = "已导出：\(url.lastPathComponent)"
        } catch {
            experimentError = "导出失败：\(error.localizedDescription)"
        }
    }

    private func receive(_ snapshot: FlyStateSnapshot) {
        self.snapshot = snapshot
        if snapshot.sampledAt.timeIntervalSince(lastTraceAt) >= 0.2 {
            traceSequence += 1
            liveTrace.append(NeuralLiveTracePoint(
                id: traceSequence,
                date: snapshot.sampledAt,
                sensory: snapshot.wholeCNSSensoryActivity ?? 0,
                central: snapshot.wholeCNSCentralComplexActivity ?? 0,
                descending: snapshot.wholeCNSDescendingActivity ?? 0,
                motor: snapshot.wholeCNSMotorActivity ?? 0,
                dopamine: snapshot.wholeCNSDopamineLevel ?? 0
            ))
            if liveTrace.count > 150 {
                liveTrace.removeFirst(liveTrace.count - 150)
            }
            lastTraceAt = snapshot.sampledAt
        }
        if let selectedBodyID {
            selectedNeuron = runtime.inspectFullCNSNeuron(bodyID: selectedBodyID)
        }
    }

    private func parseBodyIDs(_ text: String) -> [UInt64] {
        let separators = CharacterSet(charactersIn: ",，;； \n\t")
        return Array(Set(text.components(separatedBy: separators).compactMap {
            UInt64($0.trimmingCharacters(in: .whitespacesAndNewlines))
        })).sorted()
    }

    private func safeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "experiment" : cleaned
    }
}

struct NeuralLabView: View {
    @StateObject private var controller: NeuralLabController

    init(runtime: RuntimeController) {
        _controller = StateObject(wrappedValue: NeuralLabController(runtime: runtime))
    }

    var body: some View {
        VStack(spacing: 0) {
            NeuralLabHeader(controller: controller)
            Divider().overlay(NeuralLabPalette.border)
            HStack(spacing: 0) {
                NeuralLabSidebar(controller: controller)
                Divider().overlay(NeuralLabPalette.border)
                Group {
                    switch controller.selectedPage {
                    case .live:
                        NeuralLivePage(controller: controller)
                    case .selfModel:
                        FunctionalSelfPage(controller: controller)
                    case .cognitive:
                        DevelopmentalSelfPage(controller: controller)
                    case .neurons:
                        NeuronBrowserPage(controller: controller)
                    case .experiment:
                        ExperimentConsolePage(controller: controller)
                    case .results:
                        ExperimentResultsPage(controller: controller)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(NeuralLabPalette.background)
        .preferredColorScheme(.dark)
    }
}

private struct NeuralLabHeader: View {
    @ObservedObject var controller: NeuralLabController

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(LinearGradient(
                        colors: [NeuralLabPalette.cyan.opacity(0.95), NeuralLabPalette.green.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: "ant.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.82))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("数字果蝇 · 神经实验室")
                    .font(.headline)
                Text("MaleCNS v1.0 · observed graph / modeled dynamics")
                    .font(.caption)
                    .foregroundStyle(NeuralLabPalette.secondary)
            }

            Spacer()
            NeuralStatusPill(
                icon: "point.3.connected.trianglepath.dotted",
                text: "\((controller.snapshot.wholeCNSActiveNeuronCount ?? 0).formatted()) 活跃",
                color: NeuralLabPalette.green
            )
            NeuralStatusPill(
                icon: "bolt.fill",
                text: "\((controller.snapshot.wholeCNSEdgeEventCount ?? 0).formatted()) 传播",
                color: NeuralLabPalette.amber
            )
            NeuralStatusPill(
                icon: "speedometer",
                text: "\((controller.snapshot.wholeCNSRealTimeFactor ?? 0).formatted(.number.precision(.fractionLength(2))))×",
                color: NeuralLabPalette.cyan
            )
            NeuralStatusPill(
                icon: "scope",
                text: "自我置信 \((controller.snapshot.functionalSelf?.confidence ?? 0).formatted(.percent.precision(.fractionLength(0))))",
                color: NeuralLabPalette.violet
            )
            Circle()
                .fill(controller.snapshot.wholeCNSEventBudgetSaturated == true ? .orange : NeuralLabPalette.green)
                .frame(width: 8, height: 8)
                .shadow(color: NeuralLabPalette.green.opacity(0.7), radius: 5)
        }
        .padding(.horizontal, 20)
        .frame(height: 66)
        .background(NeuralLabPalette.panel.opacity(0.96))
    }
}

private struct NeuralStatusPill: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 1))
    }
}

private struct NeuralLabSidebar: View {
    @ObservedObject var controller: NeuralLabController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("工作区")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NeuralLabPalette.tertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 3)
            ForEach(NeuralLabPage.allCases) { page in
                Button {
                    controller.selectPage(page)
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: page.systemImage)
                            .frame(width: 19)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(page.title).font(.subheadline.weight(.medium))
                            Text(page.subtitle)
                                .font(.caption2)
                                .foregroundStyle(controller.selectedPage == page
                                    ? Color.white.opacity(0.68)
                                    : NeuralLabPalette.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(controller.selectedPage == page ? .white : NeuralLabPalette.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        controller.selectedPage == page
                            ? NeuralLabPalette.cyan.opacity(0.15)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay {
                        if controller.selectedPage == page {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(NeuralLabPalette.cyan.opacity(0.28), lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
            VStack(alignment: .leading, spacing: 7) {
                Text(controller.snapshot.behavior.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(controller.snapshot.reason)
                    .font(.caption2)
                    .foregroundStyle(NeuralLabPalette.secondary)
                    .lineLimit(4)
                Divider().overlay(NeuralLabPalette.border)
                Text("graph \(String((controller.snapshot.wholeCNSGraphSHA256 ?? "unavailable").prefix(12)))…")
                    .font(.caption2.monospaced())
                    .foregroundStyle(NeuralLabPalette.tertiary)
            }
            .padding(12)
            .background(NeuralLabPalette.card, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(14)
        .frame(width: 205)
        .background(NeuralLabPalette.sidebar)
    }
}

private struct NeuralLivePage: View {
    @ObservedObject var controller: NeuralLabController

    private let metricColumns = [GridItem(.adaptive(minimum: 165), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LabPageTitle(
                    eyebrow: "LIVE CONNECTOME",
                    title: "实时脑窗",
                    subtitle: "观察低维桌面感觉如何进入全 CNS，再调制工程动作竞争。"
                )

                LazyVGrid(columns: metricColumns, spacing: 12) {
                    LabMetricCard(
                        title: "神经元",
                        value: (controller.snapshot.wholeCNSNodeCount ?? 0).formatted(),
                        detail: "全部 Traced body",
                        color: NeuralLabPalette.cyan
                    )
                    LabMetricCard(
                        title: "当前放电",
                        value: (controller.snapshot.wholeCNSSpikeCount ?? 0).formatted(),
                        detail: "本模拟周期",
                        color: NeuralLabPalette.amber
                    )
                    LabMetricCard(
                        title: "动作竞争",
                        value: "\(controller.snapshot.activeControllerNeuronCount ?? 0)/\(controller.snapshot.controllerNeuronCount ?? 0)",
                        detail: controller.snapshot.selectedActionNeuron ?? "无胜出单元",
                        color: NeuralLabPalette.violet
                    )
                    LabMetricCard(
                        title: "实时倍率",
                        value: "\((controller.snapshot.wholeCNSRealTimeFactor ?? 0).formatted(.number.precision(.fractionLength(2))))×",
                        detail: controller.snapshot.wholeCNSEventBudgetSaturated == true ? "事件预算已触发" : "事件预算正常",
                        color: NeuralLabPalette.green
                    )
                }

                HStack(alignment: .top, spacing: 14) {
                    LiveBrainMap(snapshot: controller.snapshot)
                        .frame(minWidth: 420, minHeight: 330)
                    SignalReadoutPanel(snapshot: controller.snapshot)
                        .frame(width: 250)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("最近 30 秒群体活动", systemImage: "chart.xyaxis.line")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("每 0.2 秒采样")
                            .font(.caption)
                            .foregroundStyle(NeuralLabPalette.tertiary)
                    }
                    if controller.liveTrace.isEmpty {
                        LabEmptyState(text: "正在收集实时活动…")
                            .frame(height: 170)
                    } else {
                        Chart(controller.liveTrace) { point in
                            LineMark(
                                x: .value("时间", point.date),
                                y: .value("活动", point.sensory),
                                series: .value("群体", "感觉")
                            )
                            .foregroundStyle(by: .value("群体", "感觉"))
                            LineMark(
                                x: .value("时间", point.date),
                                y: .value("活动", point.central),
                                series: .value("群体", "中央复合体")
                            )
                            .foregroundStyle(by: .value("群体", "中央复合体"))
                            LineMark(
                                x: .value("时间", point.date),
                                y: .value("活动", point.descending),
                                series: .value("群体", "下行")
                            )
                            .foregroundStyle(by: .value("群体", "下行"))
                            LineMark(
                                x: .value("时间", point.date),
                                y: .value("活动", point.motor),
                                series: .value("群体", "运动")
                            )
                            .foregroundStyle(by: .value("群体", "运动"))
                        }
                        .chartForegroundStyleScale([
                            "感觉": NeuralLabPalette.cyan,
                            "中央复合体": NeuralLabPalette.violet,
                            "下行": NeuralLabPalette.amber,
                            "运动": NeuralLabPalette.green,
                        ])
                        .chartLegend(position: .top, alignment: .leading, spacing: 14)
                        .frame(height: 210)
                    }
                }
                .labCard()
            }
            .padding(22)
        }
        .background(NeuralLabPalette.background)
    }
}

private struct LiveBrainMap: View {
    let snapshot: FlyStateSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("功能群脑图", systemImage: "brain.head.profile")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("群体读出 · 非解剖比例")
                    .font(.caption2)
                    .foregroundStyle(NeuralLabPalette.tertiary)
            }
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    Canvas { context, _ in
                        let brainRect = CGRect(
                            x: size.width * 0.16,
                            y: size.height * 0.08,
                            width: size.width * 0.68,
                            height: size.height * 0.50
                        )
                        let left = CGRect(
                            x: brainRect.minX,
                            y: brainRect.minY,
                            width: brainRect.width * 0.54,
                            height: brainRect.height
                        )
                        let right = CGRect(
                            x: brainRect.midX - brainRect.width * 0.04,
                            y: brainRect.minY,
                            width: brainRect.width * 0.54,
                            height: brainRect.height
                        )
                        context.fill(Path(ellipseIn: left), with: .color(NeuralLabPalette.cyan.opacity(0.09)))
                        context.fill(Path(ellipseIn: right), with: .color(NeuralLabPalette.cyan.opacity(0.09)))
                        context.stroke(Path(ellipseIn: left), with: .color(NeuralLabPalette.cyan.opacity(0.34)), lineWidth: 1.4)
                        context.stroke(Path(ellipseIn: right), with: .color(NeuralLabPalette.cyan.opacity(0.34)), lineWidth: 1.4)

                        var cord = Path()
                        cord.move(to: CGPoint(x: size.width * 0.5, y: brainRect.maxY - 4))
                        cord.addCurve(
                            to: CGPoint(x: size.width * 0.5, y: size.height * 0.93),
                            control1: CGPoint(x: size.width * 0.47, y: size.height * 0.67),
                            control2: CGPoint(x: size.width * 0.53, y: size.height * 0.78)
                        )
                        context.stroke(cord, with: .color(NeuralLabPalette.amber.opacity(0.52)), lineWidth: 5)
                        context.stroke(cord, with: .color(NeuralLabPalette.background), lineWidth: 1.5)

                        for row in 0..<3 {
                            let y = size.height * (0.68 + Double(row) * 0.105)
                            let rect = CGRect(x: size.width * 0.40, y: y, width: size.width * 0.20, height: 20)
                            context.fill(Path(roundedRect: rect, cornerRadius: 10), with: .color(NeuralLabPalette.green.opacity(0.10)))
                            context.stroke(Path(roundedRect: rect, cornerRadius: 10), with: .color(NeuralLabPalette.green.opacity(0.38)), lineWidth: 1)
                        }
                    }

                    BrainPulse(
                        label: "感觉",
                        value: snapshot.wholeCNSSensoryActivity ?? 0,
                        color: NeuralLabPalette.cyan
                    )
                    .position(x: size.width * 0.23, y: size.height * 0.23)
                    BrainPulse(
                        label: "CX",
                        value: snapshot.wholeCNSCentralComplexActivity ?? 0,
                        color: NeuralLabPalette.violet
                    )
                    .position(x: size.width * 0.50, y: size.height * 0.34)
                    BrainPulse(
                        label: "下行",
                        value: snapshot.wholeCNSDescendingActivity ?? 0,
                        color: NeuralLabPalette.amber
                    )
                    .position(x: size.width * 0.50, y: size.height * 0.62)
                    BrainPulse(
                        label: "运动",
                        value: snapshot.wholeCNSMotorActivity ?? 0,
                        color: NeuralLabPalette.green
                    )
                    .position(x: size.width * 0.68, y: size.height * 0.83)
                    BrainPulse(
                        label: "DA",
                        value: snapshot.wholeCNSDopamineLevel ?? 0,
                        color: NeuralLabPalette.rose
                    )
                    .position(x: size.width * 0.76, y: size.height * 0.25)
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [NeuralLabPalette.card, NeuralLabPalette.panel.opacity(0.86)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuralLabPalette.border, lineWidth: 1))
    }
}

private struct BrainPulse: View {
    let label: String
    let value: Double
    let color: Color

    private var intensity: Double {
        min(max(value * 28, 0.08), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.08 + intensity * 0.18))
                .frame(width: 62, height: 62)
                .blur(radius: 6)
            Circle()
                .fill(color.opacity(0.18 + intensity * 0.52))
                .frame(width: 34 + intensity * 13, height: 34 + intensity * 13)
                .shadow(color: color.opacity(intensity * 0.75), radius: 10)
            VStack(spacing: 1) {
                Text(label).font(.caption2.weight(.bold))
                Text(value.formatted(.percent.precision(.fractionLength(1))))
                    .font(.system(size: 9, design: .monospaced))
            }
            .foregroundStyle(.white.opacity(0.94))
        }
        .frame(width: 72, height: 72)
    }
}

private struct SignalReadoutPanel: View {
    let snapshot: FlyStateSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("闭环读出", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
            SignalRow(label: "感觉输入", value: snapshot.wholeCNSSensoryActivity ?? 0, color: NeuralLabPalette.cyan)
            SignalArrow()
            SignalRow(label: "中央复合体", value: snapshot.wholeCNSCentralComplexActivity ?? 0, color: NeuralLabPalette.violet)
            SignalArrow()
            SignalRow(label: "下行输出", value: snapshot.wholeCNSDescendingActivity ?? 0, color: NeuralLabPalette.amber)
            SignalArrow()
            SignalRow(label: "运动群", value: snapshot.wholeCNSMotorActivity ?? 0, color: NeuralLabPalette.green)
            SignalArrow()
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.selectedActionNeuron ?? "ENG-ACT-IDLE")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(NeuralLabPalette.green)
                Text(snapshot.behavior.displayName)
                    .font(.title3.weight(.semibold))
                Text("竞争差 \((snapshot.actionConfidence ?? 0).formatted(.percent.precision(.fractionLength(0))))")
                    .font(.caption2)
                    .foregroundStyle(NeuralLabPalette.secondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NeuralLabPalette.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            Spacer(minLength: 0)
            Text("observed / predicted → fitted / assumed")
                .font(.caption2.monospaced())
                .foregroundStyle(NeuralLabPalette.tertiary)
        }
        .padding(16)
        .background(NeuralLabPalette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuralLabPalette.border, lineWidth: 1))
    }
}

private struct SignalRow: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(value.formatted(.percent.precision(.fractionLength(2))))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(color)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(color)
                        .frame(width: max(3, proxy.size.width * min(max(value * 16, 0), 1)))
                }
            }
            .frame(height: 5)
        }
    }
}

private struct SignalArrow: View {
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.caption2)
            .foregroundStyle(NeuralLabPalette.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, -5)
    }
}

private struct FunctionalSelfPage: View {
    @ObservedObject var controller: NeuralLabController

    private let metricColumns = [GridItem(.adaptive(minimum: 155), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LabPageTitle(
                    eyebrow: "FUNCTIONAL SELF · ENGINEERED",
                    title: "功能性自我认知",
                    subtitle: "用身体连续性、行动后果预测、内外因归属、经历记忆与不确定度构成可消融、可证伪的自我模型。"
                )

                if let selfState = controller.snapshot.functionalSelf {
                    LazyVGrid(columns: metricColumns, spacing: 12) {
                        LabMetricCard(
                            title: "身体一致性",
                            value: selfState.bodilyCoherence.formatted(.percent.precision(.fractionLength(0))),
                            detail: selfState.identityContinuity ? "个体身份连续" : "身份连续性中断",
                            color: NeuralLabPalette.cyan
                        )
                        LabMetricCard(
                            title: "能动性归因",
                            value: selfState.agencyScore.formatted(.percent.precision(.fractionLength(0))),
                            detail: selfState.causalAttribution.displayName,
                            color: attributionColor(selfState.causalAttribution)
                        )
                        LabMetricCard(
                            title: "模型置信度",
                            value: selfState.confidence.formatted(.percent.precision(.fractionLength(0))),
                            detail: "不确定度 \(selfState.uncertainty.formatted(.percent.precision(.fractionLength(0))))",
                            color: NeuralLabPalette.violet
                        )
                        LabMetricCard(
                            title: "预测误差",
                            value: selfState.predictionError.formatted(.percent.precision(.fractionLength(0))),
                            detail: "感觉可靠度 \(selfState.sensorReliability.formatted(.percent.precision(.fractionLength(0))))",
                            color: selfState.predictionError > 0.45
                                ? NeuralLabPalette.rose : NeuralLabPalette.green
                        )
                    }

                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("当前因果判断", systemImage: "scope")
                                .font(.headline)
                            Text(selfState.causalAttribution.displayName)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(attributionColor(selfState.causalAttribution))
                            Text(selfState.explanation)
                                .font(.subheadline)
                                .foregroundStyle(NeuralLabPalette.secondary)

                            Divider().overlay(NeuralLabPalette.border)
                            SelfComparisonRow(
                                title: "位移",
                                predicted: selfState.predictedDisplacement,
                                observed: selfState.observedDisplacement,
                                digits: 4
                            )
                            SelfComparisonRow(
                                title: "能量变化",
                                predicted: selfState.predictedEnergyDelta,
                                observed: selfState.observedEnergyDelta,
                                digits: 6
                            )
                            HStack {
                                InspectorRow(
                                    label: "前进增益",
                                    value: selfState.learnedForwardGain.formatted(.number.precision(.fractionLength(2)))
                                )
                                InspectorRow(
                                    label: "转向增益",
                                    value: selfState.learnedTurnGain.formatted(.number.precision(.fractionLength(2)))
                                )
                            }
                            InspectorRow(
                                label: "行动能力",
                                value: selfState.actionCapability.formatted(.percent.precision(.fractionLength(0)))
                            )
                            Divider().overlay(NeuralLabPalette.border)
                            Text("分布式自我通道")
                                .font(.caption.weight(.semibold))
                            LiveValueBar(label: "视觉运动", value: selfState.visualChannel, range: 0...1, color: NeuralLabPalette.cyan)
                            LiveValueBar(label: "本体感觉", value: selfState.proprioceptiveChannel, range: 0...1, color: NeuralLabPalette.green)
                            LiveValueBar(label: "内脏状态", value: selfState.visceralChannel, range: 0...1, color: NeuralLabPalette.amber)
                            LiveValueBar(label: "联想记忆", value: selfState.memoryChannel, range: 0...1, color: NeuralLabPalette.violet)
                        }
                        .labCard()
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 12) {
                            Label("在线干预", systemImage: "testtube.2")
                                .font(.headline)
                            Text("直接作用于正在生活的果蝇，用即时读数检验模型。")
                                .font(.caption)
                                .foregroundStyle(NeuralLabPalette.secondary)
                            Button("施加外力位移") { controller.displaceFlyExternally() }
                                .accessibilityIdentifier("functional-self-displace")
                            Button("遮蔽感觉 4 秒") { controller.maskSenses() }
                                .accessibilityIdentifier("functional-self-mask")
                            Button("反转转向 5 秒") { controller.reverseSteering() }
                                .accessibilityIdentifier("functional-self-reverse")
                            Text("预期：外力被归为外界；遮蔽提高不确定度；转向反转先产生误差，再在线学习新的转向增益。")
                                .font(.caption2)
                                .foregroundStyle(NeuralLabPalette.tertiary)
                        }
                        .buttonStyle(.bordered)
                        .labCard()
                        .frame(width: 245)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("自传式经历", systemImage: "clock.arrow.circlepath")
                                .font(.headline)
                            Spacer()
                            Text("\(selfState.episodes.count) / \(FunctionalSelfState.maximumEpisodeCount) · revision \(selfState.episodeRevision)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(NeuralLabPalette.tertiary)
                        }
                        if selfState.episodes.isEmpty {
                            Text("正在等待第一个有区分度的行动结果…")
                                .font(.caption)
                                .foregroundStyle(NeuralLabPalette.secondary)
                        } else {
                            ForEach(Array(selfState.episodes.reversed())) { episode in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(attributionColor(episode.attribution))
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text("tick \(episode.tick) · \(episode.behavior.displayName)")
                                                .font(.caption.monospaced().weight(.semibold))
                                            Text(episode.attribution.displayName)
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(attributionColor(episode.attribution))
                                            Spacer()
                                            Text(episode.recordedAt.formatted(date: .omitted, time: .standard))
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(NeuralLabPalette.tertiary)
                                        }
                                        Text(episode.summary)
                                            .font(.caption)
                                            .foregroundStyle(NeuralLabPalette.secondary)
                                        Text("\(episode.actionNeuron) · 误差 \(episode.predictionError.formatted(.percent.precision(.fractionLength(0)))) · 置信 \(episode.confidence.formatted(.percent.precision(.fractionLength(0))))")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(NeuralLabPalette.tertiary)
                                    }
                                }
                                if episode.id != selfState.episodes.first?.id {
                                    Divider().overlay(NeuralLabPalette.border)
                                }
                            }
                        }
                    }
                    .labCard()

                    Text("边界：此页显示的是工程层的功能性自我认知，不是主观体验证明。MaleCNS v1.0 为感觉、中央复合体和下行通路提供 observed 结构约束；预测器、归因阈值与置信度更新为 engineered/modelled。")
                        .font(.caption)
                        .foregroundStyle(NeuralLabPalette.tertiary)
                } else {
                    LabEmptyState(text: "当前快照还没有功能性自我模型状态")
                        .frame(minHeight: 420)
                        .labCard()
                }
            }
            .padding(22)
        }
        .background(NeuralLabPalette.background)
    }

    private func attributionColor(_ attribution: SelfCausalAttribution) -> Color {
        switch attribution {
        case .selfGenerated: NeuralLabPalette.green
        case .external: NeuralLabPalette.rose
        case .mixed: NeuralLabPalette.amber
        case .uncertain: NeuralLabPalette.violet
        }
    }
}

private struct DevelopmentalSelfPage: View {
    @ObservedObject var controller: NeuralLabController

    private let metricColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LabPageTitle(
                    eyebrow: "v1.3 → v1.5 · ENGINEERED / MODELLED",
                    title: "认知进阶",
                    subtitle: "从反事实行动、校准的不确定性，发展到长期目标、语义自我以及自己 / 他者区分。"
                )

                if let counterfactual = controller.snapshot.counterfactualSelf,
                   let semantic = controller.snapshot.semanticSelf,
                   let social = controller.snapshot.socialSelf {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("v1.3 · 反事实自我与元认知", systemImage: "arrow.triangle.branch")
                                .font(.headline)
                            Spacer()
                            Text(counterfactual.shouldProbe ? "主动求证" : "执行当前计划")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(counterfactual.shouldProbe
                                    ? NeuralLabPalette.amber : NeuralLabPalette.green)
                        }
                        LazyVGrid(columns: metricColumns, spacing: 12) {
                            LabMetricCard(
                                title: "自身原因",
                                value: counterfactual.selfHypothesisProbability.formatted(.percent.precision(.fractionLength(0))),
                                detail: "不读取实验标签",
                                color: NeuralLabPalette.green
                            )
                            LabMetricCard(
                                title: "外界原因",
                                value: counterfactual.worldHypothesisProbability.formatted(.percent.precision(.fractionLength(0))),
                                detail: "盲测命中 \(counterfactual.blindExternalEventCount)",
                                color: NeuralLabPalette.rose
                            )
                            LabMetricCard(
                                title: "认知不确定",
                                value: counterfactual.epistemicDrive.formatted(.percent.precision(.fractionLength(0))),
                                detail: "歧义 \(counterfactual.ambiguity.formatted(.percent.precision(.fractionLength(0))))",
                                color: NeuralLabPalette.violet
                            )
                            LabMetricCard(
                                title: "校准误差",
                                value: counterfactual.calibrationError.formatted(.percent.precision(.fractionLength(0))),
                                detail: "Brier \(counterfactual.brierScore.formatted(.number.precision(.fractionLength(3)))) · n=\(counterfactual.calibrationSampleCount)",
                                color: NeuralLabPalette.cyan
                            )
                        }
                        Text(counterfactual.explanation)
                            .font(.caption)
                            .foregroundStyle(NeuralLabPalette.secondary)

                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("候选未来").font(.caption.weight(.semibold))
                                Spacer()
                                Text("效用 · 信息 · 威胁 · 置信")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(NeuralLabPalette.tertiary)
                            }
                            ForEach(
                                counterfactual.candidates.sorted { $0.expectedUtility > $1.expectedUtility }
                            ) { candidate in
                                HStack(spacing: 10) {
                                    Image(systemName: candidate.behavior.systemImage)
                                        .frame(width: 18)
                                    Text(candidate.behavior.displayName)
                                        .frame(width: 76, alignment: .leading)
                                    Text(candidate.expectedUtility.formatted(.number.precision(.fractionLength(2))))
                                        .foregroundStyle(candidate.behavior == counterfactual.selectedBehavior
                                            ? NeuralLabPalette.green : Color.white)
                                    Spacer()
                                    Text(candidate.expectedInformationGain.formatted(.percent.precision(.fractionLength(0))))
                                    Text(candidate.predictedThreatExposure.formatted(.percent.precision(.fractionLength(0))))
                                    Text(candidate.confidence.formatted(.percent.precision(.fractionLength(0))))
                                }
                                .font(.caption.monospacedDigit())
                            }
                        }
                        Button("施加隐藏阵风（盲测）") { controller.applyHiddenWind() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("cognitive-hidden-wind")
                    }
                    .labCard()

                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("v1.4 · 长期目标与语义自我", systemImage: "scope")
                                .font(.headline)
                            Text(semantic.activeGoal.displayName)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(NeuralLabPalette.amber)
                            Text(semantic.narrativeSummary)
                                .font(.caption)
                                .foregroundStyle(NeuralLabPalette.secondary)
                            InspectorRow(
                                label: "目标稳定度",
                                value: semantic.goalStability.formatted(.percent.precision(.fractionLength(0)))
                            )
                            InspectorRow(
                                label: "经历整合",
                                value: "\(semantic.consolidationCount) 次"
                            )
                            Divider().overlay(NeuralLabPalette.border)
                            Text("个体偏好").font(.caption.weight(.semibold))
                            LiveValueBar(label: "探索", value: semantic.preferences.exploration, range: 0...1, color: NeuralLabPalette.cyan)
                            LiveValueBar(label: "谨慎", value: semantic.preferences.caution, range: 0...1, color: NeuralLabPalette.rose)
                            LiveValueBar(label: "节能", value: semantic.preferences.energyConservation, range: 0...1, color: NeuralLabPalette.green)
                            LiveValueBar(label: "清洁", value: semantic.preferences.cleanliness, range: 0...1, color: NeuralLabPalette.amber)
                            LiveValueBar(label: "社交兴趣", value: semantic.preferences.socialInterest, range: 0...1, color: NeuralLabPalette.violet)
                            Button("制造目标冲突 5 秒") { controller.triggerGoalConflict() }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("cognitive-goal-conflict")
                        }
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("已整合的自我知识")
                                .font(.caption.weight(.semibold))
                            if semantic.beliefs.isEmpty {
                                Text("等待至少 10 个计算周期形成第一轮语义整合…")
                                    .font(.caption)
                                    .foregroundStyle(NeuralLabPalette.secondary)
                            } else {
                                ForEach(semantic.beliefs) { belief in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(belief.displayName).font(.caption.weight(.medium))
                                            Spacer()
                                            Text(belief.value.formatted(.percent.precision(.fractionLength(0))))
                                                .font(.caption.monospacedDigit())
                                        }
                                        Text("置信 \(belief.confidence.formatted(.percent.precision(.fractionLength(0)))) · 证据 \(belief.evidenceCount)")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(NeuralLabPalette.tertiary)
                                        Text(belief.summary)
                                            .font(.caption2)
                                            .foregroundStyle(NeuralLabPalette.secondary)
                                    }
                                    Divider().overlay(NeuralLabPalette.border)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .labCard()

                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Label("v1.5 · 自己 / 他者模型", systemImage: "person.2.wave.2")
                                .font(.headline)
                            Spacer()
                            Text(social.otherPresent ? (social.trackedOtherID ?? "OTHER") : "无他者")
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(social.otherPresent
                                    ? NeuralLabPalette.cyan : NeuralLabPalette.tertiary)
                        }
                        LazyVGrid(columns: metricColumns, spacing: 12) {
                            LabMetricCard(
                                title: "自己 / 他者分离",
                                value: social.selfOtherSeparation.formatted(.percent.precision(.fractionLength(0))),
                                detail: social.attribution.displayName,
                                color: NeuralLabPalette.cyan
                            )
                            LabMetricCard(
                                title: "他者能动性",
                                value: social.otherAgencyProbability.formatted(.percent.precision(.fractionLength(0))),
                                detail: "观察运动 \(social.observedOtherMotion.formatted(.percent.precision(.fractionLength(0))))",
                                color: NeuralLabPalette.violet
                            )
                            LabMetricCard(
                                title: "共同作用",
                                value: social.jointActionProbability.formatted(.percent.precision(.fractionLength(0))),
                                detail: "预测响应 \(social.predictedOtherResponse.formatted(.percent.precision(.fractionLength(0))))",
                                color: NeuralLabPalette.green
                            )
                            LabMetricCard(
                                title: "社会警觉",
                                value: social.vigilance.formatted(.percent.precision(.fractionLength(0))),
                                detail: "亲和 \(social.affiliation.formatted(.percent.precision(.fractionLength(0))))",
                                color: NeuralLabPalette.rose
                            )
                        }
                        Text(social.explanation)
                            .font(.caption)
                            .foregroundStyle(NeuralLabPalette.secondary)
                        HStack {
                            Button("引入响应型他者 6 秒") {
                                controller.introduceOtherAgent(contingent: true)
                            }
                            .accessibilityIdentifier("cognitive-other-contingent")
                            Button("引入独立他者 6 秒") {
                                controller.introduceOtherAgent(contingent: false)
                            }
                            .accessibilityIdentifier("cognitive-other-independent")
                        }
                        .buttonStyle(.bordered)
                    }
                    .labCard()

                    Text("来源边界：MaleCNS v1.0 只约束上游 observed 连接结构及派生感觉/中央复合体/下降读出；反事实候选、概率假设、长期目标、偏好、语义信念和他者模型均为 engineered/modelled。这里没有主观体验或真实果蝇社会认知声明。")
                        .font(.caption)
                        .foregroundStyle(NeuralLabPalette.tertiary)
                } else {
                    LabEmptyState(text: "当前快照还没有 v1.3–v1.5 认知自我状态")
                        .frame(minHeight: 420)
                        .labCard()
                }
            }
            .padding(22)
        }
        .background(NeuralLabPalette.background)
    }
}

private struct SelfComparisonRow: View {
    let title: String
    let predicted: Double
    let observed: Double
    let digits: Int

    var body: some View {
        HStack {
            Text(title).foregroundStyle(NeuralLabPalette.secondary)
            Spacer()
            Text("预测 \(predicted.formatted(.number.precision(.fractionLength(digits))))")
                .foregroundStyle(NeuralLabPalette.cyan)
            Text("实测 \(observed.formatted(.number.precision(.fractionLength(digits))))")
                .foregroundStyle(NeuralLabPalette.amber)
        }
        .font(.caption.monospacedDigit())
    }
}

private struct NeuronBrowserPage: View {
    @ObservedObject var controller: NeuralLabController

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                LabPageTitle(
                    eyebrow: "165,122 TRACED BODIES",
                    title: "神经元浏览器",
                    subtitle: "按 body ID、已收录的回路类型、角色、递质与侧别筛选。"
                )
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(NeuralLabPalette.tertiary)
                        TextField("body ID、DNg13、LoVP92、VES200m 或 KC 类型", text: $controller.searchText)
                            .textFieldStyle(.plain)
                            .onSubmit { controller.refreshNeuronResults() }
                        if !controller.searchText.isEmpty {
                            Button {
                                controller.searchText = ""
                                controller.refreshNeuronResults()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(NeuralLabPalette.tertiary)
                        }
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(NeuralLabPalette.card, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(NeuralLabPalette.border, lineWidth: 1))

                    Picker("角色", selection: $controller.roleFilter) {
                        ForEach(NeuralRoleFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 142)
                    Picker("递质", selection: $controller.transmitterFilter) {
                        ForEach(NeuralTransmitterFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 126)
                    Picker("侧别", selection: $controller.hemisphereFilter) {
                        ForEach(NeuralHemisphereFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 112)
                    Button("查询") { controller.refreshNeuronResults() }
                        .buttonStyle(.borderedProminent)
                        .tint(NeuralLabPalette.cyan)
                }
            }
            .padding(22)

            Divider().overlay(NeuralLabPalette.border)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Text("结果 \(controller.neuronResults.count)")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("最多显示 120 个")
                            .font(.caption2)
                            .foregroundStyle(NeuralLabPalette.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 38)

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(controller.neuronResults) { neuron in
                                NeuronResultRow(
                                    neuron: neuron,
                                    isSelected: controller.selectedBodyID == neuron.bodyID
                                ) {
                                    controller.selectNeuron(neuron)
                                }
                            }
                        }
                        .padding(10)
                    }
                }
                .frame(minWidth: 420)

                Divider().overlay(NeuralLabPalette.border)
                NeuronInspector(controller: controller)
                    .frame(width: 330)
            }
        }
        .background(NeuralLabPalette.background)
        .onChange(of: controller.roleFilter) { _, _ in controller.refreshNeuronResults() }
        .onChange(of: controller.transmitterFilter) { _, _ in controller.refreshNeuronResults() }
        .onChange(of: controller.hemisphereFilter) { _, _ in controller.refreshNeuronResults() }
    }
}

private struct NeuronResultRow: View {
    let neuron: FullCNSNeuronObservation
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(neuron.activity > 0.08 ? NeuralLabPalette.green : transmitterColor(neuron.transmitter).opacity(0.45))
                    .frame(width: 9, height: 9)
                    .shadow(color: neuron.activity > 0.08 ? NeuralLabPalette.green : .clear, radius: 4)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(neuron.annotationInstance ?? neuron.annotationType ?? "body \(neuron.bodyID)")
                            .font(.subheadline.weight(.medium))
                        if neuron.annotationInstance != nil {
                            Text("body \(neuron.bodyID)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(NeuralLabPalette.tertiary)
                        }
                    }
                    Text("\(rolesText(neuron.roles)) · \(transmitterName(neuron.transmitter)) · \(hemisphereName(neuron.hemisphere))")
                        .font(.caption2)
                        .foregroundStyle(NeuralLabPalette.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("↑\(neuron.outgoingEdgeCount.formatted())  ↓\(neuron.incomingEdgeCount.formatted())")
                        .font(.caption2.monospacedDigit())
                    Text(neuron.activity.formatted(.percent.precision(.fractionLength(1))))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(NeuralLabPalette.green)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(isSelected ? NeuralLabPalette.cyan.opacity(0.12) : NeuralLabPalette.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? NeuralLabPalette.cyan.opacity(0.42) : NeuralLabPalette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct NeuronInspector: View {
    @ObservedObject var controller: NeuralLabController

    var body: some View {
        ScrollView {
            if let neuron = controller.selectedNeuron {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(neuron.annotationInstance ?? neuron.annotationType ?? "MaleCNS neuron")
                            .font(.title2.weight(.semibold))
                        Text("body \(neuron.bodyID)")
                            .font(.callout.monospaced())
                            .foregroundStyle(NeuralLabPalette.cyan)
                        Text("node index \(neuron.nodeIndex.formatted())")
                            .font(.caption2.monospaced())
                            .foregroundStyle(NeuralLabPalette.tertiary)
                    }

                    VStack(spacing: 9) {
                        InspectorRow(label: "角色", value: rolesText(neuron.roles))
                        InspectorRow(label: "递质", value: transmitterName(neuron.transmitter))
                        InspectorRow(label: "预测置信度", value: neuron.transmitterConfidence.formatted(.percent.precision(.fractionLength(1))))
                        InspectorRow(label: "侧别", value: hemisphereName(neuron.hemisphere))
                        InspectorRow(label: "追踪质量", value: "等级 \(neuron.traceQuality)")
                        InspectorRow(label: "出边", value: neuron.outgoingEdgeCount.formatted())
                        InspectorRow(label: "入边", value: neuron.incomingEdgeCount.formatted())
                    }
                    .labCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("实时动力学").font(.subheadline.weight(.semibold))
                        LiveValueBar(label: "活动", value: neuron.activity, range: 0...1, color: NeuralLabPalette.green)
                        LiveValueBar(label: "膜电位", value: neuron.membranePotential, range: -2.5...2.5, color: NeuralLabPalette.cyan)
                        LiveValueBar(label: "eligibility", value: neuron.presynapticEligibility, range: -0.35...0.35, color: NeuralLabPalette.violet)
                    }
                    .labCard()

                    if let x = neuron.somaX, let y = neuron.somaY, let z = neuron.somaZ {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("胞体坐标").font(.caption.weight(.semibold))
                            Text("x \(x)   y \(y)   z \(z)")
                                .font(.caption.monospaced())
                                .foregroundStyle(NeuralLabPalette.secondary)
                        }
                        .labCard()
                    }

                    Button {
                        controller.useSelectedNeuronAsTarget()
                    } label: {
                        Label("在实验中使用此神经元", systemImage: "testtube.2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NeuralLabPalette.cyan)

                    Text("body ID、连接和突触计数为 observed；递质为 predicted；当前动力学为 modeled。")
                        .font(.caption2)
                        .foregroundStyle(NeuralLabPalette.tertiary)
                }
                .padding(18)
            } else {
                LabEmptyState(text: "选择一个神经元查看详情")
                    .padding(24)
            }
        }
        .background(NeuralLabPalette.panel.opacity(0.52))
    }
}

private struct ExperimentConsolePage: View {
    @ObservedObject var controller: NeuralLabController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LabPageTitle(
                    eyebrow: "CAUSAL WORKBENCH",
                    title: "实验控制台",
                    subtitle: "从相同初始状态运行独立对照组和干预组，不改变正在生活的桌面果蝇。"
                )

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Label("实验定义", systemImage: "testtube.2")
                                .font(.headline)
                            Spacer()
                            Button("载入 DNg13 预设") { controller.loadDNg13Preset() }
                                .buttonStyle(.bordered)
                        }
                        LabLabeledField(title: "实验名称") {
                            TextField("实验名称", text: $controller.experimentName)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabLabeledField(title: "目标 body ID") {
                            TextField("例如 11074, 512006", text: $controller.targetBodyIDs)
                                .textFieldStyle(.roundedBorder)
                        }
                        Text("多个 ID 使用逗号或空格分隔。当前版本按 body ID 干预，实验在隔离运行时执行。")
                            .font(.caption2)
                            .foregroundStyle(NeuralLabPalette.tertiary)

                        Picker("干预", selection: $controller.interventionMode) {
                            Text("静默").tag(FullCNSInterventionMode.silence)
                            Text("刺激").tag(FullCNSInterventionMode.stimulate)
                        }
                        .pickerStyle(.segmented)
                        if controller.interventionMode == .stimulate {
                            LabSliderRow(title: "刺激强度", value: $controller.stimulationAmplitude)
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("实验时长")
                                Spacer()
                                Text("\(controller.duration.formatted(.number.precision(.fractionLength(1)))) 秒")
                                    .monospacedDigit()
                                    .foregroundStyle(NeuralLabPalette.cyan)
                            }
                            .font(.caption)
                            Slider(value: $controller.duration, in: 0.2...3, step: 0.1)
                                .tint(NeuralLabPalette.cyan)
                        }
                    }
                    .labCard()
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 13) {
                        Label("刺激协议", systemImage: "waveform.path")
                            .font(.headline)
                        LabSliderRow(title: "左视觉运动", value: $controller.leftVisualMotion)
                        LabSliderRow(title: "右视觉运动", value: $controller.rightVisualMotion)
                        LabSliderRow(title: "气味", value: $controller.odor)
                        LabSliderRow(title: "味觉", value: $controller.taste)
                        LabSliderRow(title: "触觉", value: $controller.touch)
                        LabSliderRow(title: "本体感觉", value: $controller.proprioception)
                        LabSliderRow(title: "饥饿", value: $controller.hunger)
                        LabSliderRow(title: "奖励", value: $controller.reward)
                        LabSliderRow(title: "惩罚", value: $controller.punishment)
                    }
                    .labCard()
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(controller.experimentProgressText)
                            .font(.subheadline.weight(.medium))
                        Text("对照组与干预组使用同一连接图、动力学参数和刺激协议。")
                            .font(.caption)
                            .foregroundStyle(NeuralLabPalette.secondary)
                    }
                    Spacer()
                    if controller.isRunningExperiment {
                        ProgressView().controlSize(.small)
                    }
                    Button {
                        controller.runExperiment()
                    } label: {
                        Label("运行 A/B 实验", systemImage: "play.fill")
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(NeuralLabPalette.green)
                    .disabled(controller.isRunningExperiment)
                }
                .labCard()

                if let error = controller.experimentError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }

                Text("实验输出会记录数据集、graph SHA、干预目标、完整刺激协议、时间序列和事件预算状态。")
                    .font(.caption)
                    .foregroundStyle(NeuralLabPalette.tertiary)
            }
            .padding(22)
        }
        .background(NeuralLabPalette.background)
    }
}

private struct ExperimentResultsPage: View {
    @ObservedObject var controller: NeuralLabController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LabPageTitle(
                    eyebrow: "CONTROL VS INTERVENTION",
                    title: "对照结果",
                    subtitle: "同一图、同一刺激、同一起点，仅改变指定神经干预。"
                )

                if let result = controller.experimentResult {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: result.expectationPassed == false
                                    ? "exclamationmark.triangle.fill"
                                    : "checkmark.seal.fill")
                                    .foregroundStyle(result.expectationPassed == false ? .orange : NeuralLabPalette.green)
                                Text(result.definition.name)
                                    .font(.title3.weight(.semibold))
                            }
                            Text(result.summary)
                                .font(.subheadline)
                            Text("解析目标 \(result.resolvedTargetCount) · \(result.samples.count) 个时间点 · \(result.dataset)")
                                .font(.caption)
                                .foregroundStyle(NeuralLabPalette.secondary)
                        }
                        Spacer()
                        Button {
                            controller.exportExperimentResult()
                        } label: {
                            Label("导出 JSON", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NeuralLabPalette.cyan)
                    }
                    .labCard()

                    HStack(spacing: 12) {
                        LabMetricCard(
                            title: "对照峰值转向",
                            value: result.controlPeakAbsoluteTurnBias.formatted(.number.precision(.fractionLength(4))),
                            detail: "absolute turn bias",
                            color: NeuralLabPalette.cyan
                        )
                        LabMetricCard(
                            title: "干预峰值转向",
                            value: result.interventionPeakAbsoluteTurnBias.formatted(.number.precision(.fractionLength(4))),
                            detail: "absolute turn bias",
                            color: NeuralLabPalette.rose
                        )
                        LabMetricCard(
                            title: "转向削弱",
                            value: result.turnBiasReductionFraction.formatted(.percent.precision(.fractionLength(1))),
                            detail: "相对对照峰值",
                            color: NeuralLabPalette.green
                        )
                        LabMetricCard(
                            title: "事件预算",
                            value: result.eventBudgetSaturated ? "已触发" : "正常",
                            detail: "两组完整记录",
                            color: result.eventBudgetSaturated ? .orange : NeuralLabPalette.green
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("视觉转向时间线", systemImage: "arrow.left.and.right")
                            .font(.subheadline.weight(.semibold))
                        Chart(result.samples) { sample in
                            LineMark(
                                x: .value("模拟秒", sample.simulatedSeconds),
                                y: .value("转向偏置", sample.controlTurnBias),
                                series: .value("组别", "对照组")
                            )
                            .foregroundStyle(by: .value("组别", "对照组"))
                            .symbol(by: .value("组别", "对照组"))
                            LineMark(
                                x: .value("模拟秒", sample.simulatedSeconds),
                                y: .value("转向偏置", sample.interventionTurnBias),
                                series: .value("组别", "干预组")
                            )
                            .foregroundStyle(by: .value("组别", "干预组"))
                            .symbol(by: .value("组别", "干预组"))
                            RuleMark(y: .value("零", 0))
                                .foregroundStyle(NeuralLabPalette.tertiary.opacity(0.5))
                        }
                        .chartForegroundStyleScale([
                            "对照组": NeuralLabPalette.cyan,
                            "干预组": NeuralLabPalette.rose,
                        ])
                        .chartLegend(position: .top, alignment: .leading)
                        .frame(height: 245)
                    }
                    .labCard()

                    HStack(alignment: .top, spacing: 14) {
                        ResultComparisonCard(
                            title: "平均活跃神经元",
                            control: result.controlMeanActiveNeuronCount,
                            intervention: result.interventionMeanActiveNeuronCount,
                            format: { $0.formatted(.number.precision(.fractionLength(1))) }
                        )
                        ResultComparisonCard(
                            title: "累计边事件",
                            control: Double(result.controlTotalEdgeEvents),
                            intervention: Double(result.interventionTotalEdgeEvents),
                            format: { Int($0.rounded()).formatted() }
                        )
                        VStack(alignment: .leading, spacing: 8) {
                            Text("可重复性").font(.subheadline.weight(.semibold))
                            Text("graph \(String(result.graphSHA256.prefix(16)))…")
                                .font(.caption.monospaced())
                            Text("\(result.definition.intervention == .silence ? "静默" : "刺激") body \(result.definition.targetBodyIDs.map(String.init).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(NeuralLabPalette.secondary)
                            Text(result.createdAt.formatted(date: .abbreviated, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(NeuralLabPalette.tertiary)
                        }
                        .labCard()
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(NeuralLabPalette.cyan)
                        Text("还没有实验结果")
                            .font(.title3.weight(.semibold))
                        Text("先在实验控制台运行一次 A/B 因果实验。")
                            .foregroundStyle(NeuralLabPalette.secondary)
                        Button("前往实验控制台") {
                            controller.selectPage(.experiment)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NeuralLabPalette.cyan)
                    }
                    .frame(maxWidth: .infinity, minHeight: 420)
                    .labCard()
                }
            }
            .padding(22)
        }
        .background(NeuralLabPalette.background)
    }
}

private struct ResultComparisonCard: View {
    let title: String
    let control: Double
    let intervention: Double
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("对照组").font(.caption2).foregroundStyle(NeuralLabPalette.secondary)
                    Text(format(control)).font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(NeuralLabPalette.cyan)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("干预组").font(.caption2).foregroundStyle(NeuralLabPalette.secondary)
                    Text(format(intervention)).font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(NeuralLabPalette.rose)
                }
            }
        }
        .labCard()
        .frame(maxWidth: .infinity)
    }
}

private struct LabPageTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.caption2.monospaced().weight(.bold))
                .tracking(1.4)
                .foregroundStyle(NeuralLabPalette.cyan)
            Text(title).font(.largeTitle.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(NeuralLabPalette.secondary)
        }
    }
}

private struct LabMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(NeuralLabPalette.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(NeuralLabPalette.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(NeuralLabPalette.card, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(color.opacity(0.18), lineWidth: 1))
    }
}

private struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(NeuralLabPalette.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

private struct LiveValueBar: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let color: Color

    private var normalized: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(4))))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(color)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().fill(color).frame(width: max(3, proxy.size.width * normalized))
                }
            }
            .frame(height: 5)
        }
    }
}

private struct LabLabeledField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(NeuralLabPalette.secondary)
            content
        }
    }
}

private struct LabSliderRow: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .frame(width: 74, alignment: .leading)
            Slider(value: $value, in: 0...1)
                .tint(NeuralLabPalette.cyan)
            Text(value.formatted(.number.precision(.fractionLength(2))))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(NeuralLabPalette.cyan)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

private struct LabEmptyState: View {
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.caption).foregroundStyle(NeuralLabPalette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum NeuralLabPalette {
    static let background = Color(red: 0.035, green: 0.047, blue: 0.055)
    static let sidebar = Color(red: 0.048, green: 0.061, blue: 0.070)
    static let panel = Color(red: 0.060, green: 0.073, blue: 0.083)
    static let card = Color(red: 0.075, green: 0.090, blue: 0.100)
    static let border = Color.white.opacity(0.075)
    static let secondary = Color.white.opacity(0.66)
    static let tertiary = Color.white.opacity(0.40)
    static let cyan = Color(red: 0.21, green: 0.82, blue: 0.91)
    static let green = Color(red: 0.31, green: 0.88, blue: 0.60)
    static let amber = Color(red: 0.96, green: 0.67, blue: 0.25)
    static let violet = Color(red: 0.66, green: 0.49, blue: 0.96)
    static let rose = Color(red: 0.96, green: 0.36, blue: 0.50)
}

private extension View {
    func labCard() -> some View {
        padding(15)
            .background(NeuralLabPalette.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(NeuralLabPalette.border, lineWidth: 1))
    }
}

private func rolesText(_ roles: FullCNSNodeRole) -> String {
    var names: [String] = []
    for filter in NeuralRoleFilter.allCases where filter != .all {
        if let role = filter.role, roles.contains(role) {
            names.append(filter.title)
        }
    }
    return names.isEmpty ? "未分类" : names.joined(separator: " / ")
}

private func transmitterName(_ transmitter: FullCNSNeurotransmitter) -> String {
    switch transmitter {
    case .unclear: "未明确"
    case .acetylcholine: "乙酰胆碱"
    case .gaba: "GABA"
    case .glutamate: "谷氨酸"
    case .dopamine: "多巴胺"
    case .serotonin: "血清素"
    case .octopamine: "章鱼胺"
    case .histamine: "组胺"
    }
}

private func transmitterColor(_ transmitter: FullCNSNeurotransmitter) -> Color {
    switch transmitter {
    case .acetylcholine: NeuralLabPalette.cyan
    case .gaba, .glutamate, .histamine: NeuralLabPalette.rose
    case .dopamine: NeuralLabPalette.amber
    case .serotonin: NeuralLabPalette.violet
    case .octopamine: NeuralLabPalette.green
    case .unclear: NeuralLabPalette.tertiary
    }
}

private func hemisphereName(_ hemisphere: FullCNSHemisphere) -> String {
    switch hemisphere {
    case .unknown: "未标注"
    case .left: "左侧"
    case .right: "右侧"
    case .midline: "中线"
    }
}
