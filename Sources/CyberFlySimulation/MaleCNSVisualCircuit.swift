import Foundation

enum MaleCNSSide: String, Sendable {
    case left
    case right
}

enum MaleCNSNeurotransmitter: String, Sendable {
    case acetylcholine
    case glutamate
    case gaba
    case dopamine
    case serotonin
    case octopamine
}

struct MaleCNSNeuronDefinition: Sendable {
    let bodyID: Int64
    let cellType: String
    let instance: String
    let side: MaleCNSSide
    let neurotransmitter: MaleCNSNeurotransmitter
    let neurotransmitterConfidence: Double
}

struct MaleCNSSynapseDefinition: Sendable {
    let bodyPre: Int64
    let bodyPost: Int64
    let weight: Int
}

public struct MaleCNSCircuitOutput: Equatable, Sendable {
    public let datasetID: String
    public let circuitID: String
    public let realNeuronCount: Int
    public let activeNeuronCount: Int
    public let totalSpikes: Int
    public let meanFiringRateHz: Double
    public let loVP92RateHz: Double
    public let ves200mRateHz: Double
    public let leftDNg13RateHz: Double
    public let rightDNg13RateHz: Double
    public let turnBias: Double

    static var silent: MaleCNSCircuitOutput {
        MaleCNSCircuitOutput(
            datasetID: GeneratedMaleCNSVisualCircuitData.datasetID,
            circuitID: GeneratedMaleCNSVisualCircuitData.circuitID,
            realNeuronCount: GeneratedMaleCNSVisualCircuitData.neurons.count,
            activeNeuronCount: 0,
            totalSpikes: 0,
            meanFiringRateHz: 0,
            loVP92RateHz: 0,
            ves200mRateHz: 0,
            leftDNg13RateHz: 0,
            rightDNg13RateHz: 0,
            turnBias: 0
        )
    }
}

public struct MaleCNSVisualCircuit: Sendable {
    public static let datasetID = GeneratedMaleCNSVisualCircuitData.datasetID
    public static let circuitID = GeneratedMaleCNSVisualCircuitData.circuitID
    public static let realNeuronCount = GeneratedMaleCNSVisualCircuitData.neurons.count
    public static let sourceSHA256 = GeneratedMaleCNSVisualCircuitData.sourceSHA256

    private struct IndexedEdge: Sendable {
        let pre: Int
        let post: Int
        let weight: Double
        let sign: Double
    }

    private let neurons: [MaleCNSNeuronDefinition]
    private let edges: [IndexedEdge]
    private let incomingWeightTotals: [Double]
    private var membranePotential: [Double]
    private var refractoryRemaining: [Double]
    private var spikeTrace: [Double]
    private var smoothedTurnBias: Double

    public init() {
        let neurons = GeneratedMaleCNSVisualCircuitData.neurons
        let indexByBodyID = Dictionary(
            uniqueKeysWithValues: neurons.enumerated().map { ($0.element.bodyID, $0.offset) }
        )
        var incomingWeightTotals = Array(repeating: 0.0, count: neurons.count)
        var edges: [IndexedEdge] = []

        for edge in GeneratedMaleCNSVisualCircuitData.edges {
            guard let pre = indexByBodyID[edge.bodyPre],
                  let post = indexByBodyID[edge.bodyPost]
            else { continue }
            let modeledPath = (
                neurons[pre].cellType == "LoVP92" && neurons[post].cellType == "VES200m"
            ) || (
                neurons[pre].cellType == "LoVP92" && neurons[post].cellType == "DNg13"
            ) || (
                neurons[pre].cellType == "VES200m" && neurons[post].cellType == "DNg13"
            )
            guard modeledPath else { continue }
            let weight = Double(edge.weight)
            incomingWeightTotals[post] += weight
            edges.append(
                IndexedEdge(
                    pre: pre,
                    post: post,
                    weight: weight,
                    sign: Self.synapticSign(pre: neurons[pre], post: neurons[post])
                )
            )
        }

        self.neurons = neurons
        self.edges = edges
        self.incomingWeightTotals = incomingWeightTotals
        self.membranePotential = Array(repeating: 0, count: neurons.count)
        self.refractoryRemaining = Array(repeating: 0, count: neurons.count)
        self.spikeTrace = Array(repeating: 0, count: neurons.count)
        self.smoothedTurnBias = 0
    }

    public mutating func step(
        leftVisualMotion: Double,
        rightVisualMotion: Double,
        deltaTime rawDeltaTime: TimeInterval
    ) -> MaleCNSCircuitOutput {
        let deltaTime = min(max(rawDeltaTime, 0.001), 0.5)
        let substepCount = max(1, Int(ceil(deltaTime / 0.002)))
        let substep = deltaTime / Double(substepCount)
        let leftMotion = Self.clamp(leftVisualMotion)
        let rightMotion = Self.clamp(rightVisualMotion)
        var spikes = Array(repeating: 0, count: neurons.count)

        for _ in 0..<substepCount {
            let traceDecay = exp(-substep / 0.012)
            for index in neurons.indices {
                spikeTrace[index] *= traceDecay
                refractoryRemaining[index] = max(0, refractoryRemaining[index] - substep)
            }

            var current = Array(repeating: 0.035, count: neurons.count)
            for index in neurons.indices where neurons[index].cellType == "LoVP92" {
                let visualMotion = neurons[index].side == .left ? leftMotion : rightMotion
                current[index] += visualMotion * 1.65
            }
            for index in neurons.indices where neurons[index].cellType == "DNg13" {
                // This reduced slice omits most tonic inputs present in the full CNS.
                // A documented baseline current keeps DNg13 in an operating range
                // where the real LoVP92/VES200m weights can modulate its spikes.
                current[index] += 1.35
            }
            for edge in edges {
                let total = max(incomingWeightTotals[edge.post], 1)
                let normalizedWeight = edge.weight / total
                current[edge.post] += edge.sign * normalizedWeight * spikeTrace[edge.pre] * 3.6
            }

            for index in neurons.indices {
                guard refractoryRemaining[index] <= 0 else { continue }
                let membraneTimeConstant = 0.020
                membranePotential[index] += (
                    -membranePotential[index] + current[index]
                ) * substep / membraneTimeConstant
                membranePotential[index] = min(max(membranePotential[index], -0.45), 1.25)

                if membranePotential[index] >= 1 {
                    spikes[index] += 1
                    membranePotential[index] = 0
                    refractoryRemaining[index] = 0.008
                    spikeTrace[index] += 1
                }
            }
        }

        let totalSpikes = spikes.reduce(0, +)
        let activeNeuronCount = spikes.lazy.filter { $0 > 0 }.count
        let meanRate = Double(totalSpikes) / Double(neurons.count) / deltaTime
        let loVP92Rate = firingRate(
            for: "LoVP92",
            spikes: spikes,
            deltaTime: deltaTime
        )
        let ves200mRate = firingRate(
            for: "VES200m",
            spikes: spikes,
            deltaTime: deltaTime
        )
        let leftRate = firingRate(
            for: "DNg13",
            side: .left,
            spikes: spikes,
            deltaTime: deltaTime
        )
        let rightRate = firingRate(
            for: "DNg13",
            side: .right,
            spikes: spikes,
            deltaTime: deltaTime
        )

        let instantaneousTurnBias = min(max((rightRate - leftRate) / 80, -1), 1)
        smoothedTurnBias += (instantaneousTurnBias - smoothedTurnBias) * min(deltaTime * 8, 1)

        return MaleCNSCircuitOutput(
            datasetID: Self.datasetID,
            circuitID: Self.circuitID,
            realNeuronCount: neurons.count,
            activeNeuronCount: activeNeuronCount,
            totalSpikes: totalSpikes,
            meanFiringRateHz: meanRate,
            loVP92RateHz: loVP92Rate,
            ves200mRateHz: ves200mRate,
            leftDNg13RateHz: leftRate,
            rightDNg13RateHz: rightRate,
            turnBias: smoothedTurnBias
        )
    }

    private func firingRate(
        for cellType: String,
        side: MaleCNSSide? = nil,
        spikes: [Int],
        deltaTime: Double
    ) -> Double {
        let indices = neurons.indices.filter {
            neurons[$0].cellType == cellType
                && (side == nil || neurons[$0].side == side)
        }
        guard !indices.isEmpty else { return 0 }
        let spikeCount = indices.reduce(0) { $0 + spikes[$1] }
        return Double(spikeCount) / Double(indices.count) / deltaTime
    }

    private static func synapticSign(
        pre: MaleCNSNeuronDefinition,
        post: MaleCNSNeuronDefinition
    ) -> Double {
        switch pre.neurotransmitter {
        case .acetylcholine:
            return 1
        case .gaba:
            return -1
        case .glutamate:
            // The dataset predicts transmitter identity, not receptor sign. The
            // reduced VES200m → DNg13 pathway is modeled as inhibitory; other
            // glutamatergic edges are conservatively down-weighted.
            return pre.cellType == "VES200m" && post.cellType == "DNg13" ? -1 : -0.35
        case .dopamine, .serotonin, .octopamine:
            return 0.2
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
