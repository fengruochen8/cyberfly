public struct SimulationConfiguration: Equatable, Sendable {
    public var basalEnergyCostPerSecond: Double
    public var walkingEnergyMultiplier: Double
    public var flightEnergyMultiplier: Double
    public var feedingEnergyPerSecond: Double
    public var fatigueGainPerSecond: Double
    public var restRecoveryPerSecond: Double
    public var groomingRecoveryPerSecond: Double
    public var naturalContaminationPerSecond: Double
    public var torporEnergyThreshold: Double
    public var permanentDeath: Bool

    public init(
        basalEnergyCostPerSecond: Double = 1 / (36 * 60 * 60),
        walkingEnergyMultiplier: Double = 2.2,
        flightEnergyMultiplier: Double = 11,
        feedingEnergyPerSecond: Double = 0.035,
        fatigueGainPerSecond: Double = 0.004,
        restRecoveryPerSecond: Double = 0.025,
        groomingRecoveryPerSecond: Double = 0.12,
        naturalContaminationPerSecond: Double = 1 / (5 * 60 * 60),
        torporEnergyThreshold: Double = 0.025,
        permanentDeath: Bool = false
    ) {
        self.basalEnergyCostPerSecond = basalEnergyCostPerSecond
        self.walkingEnergyMultiplier = walkingEnergyMultiplier
        self.flightEnergyMultiplier = flightEnergyMultiplier
        self.feedingEnergyPerSecond = feedingEnergyPerSecond
        self.fatigueGainPerSecond = fatigueGainPerSecond
        self.restRecoveryPerSecond = restRecoveryPerSecond
        self.groomingRecoveryPerSecond = groomingRecoveryPerSecond
        self.naturalContaminationPerSecond = naturalContaminationPerSecond
        self.torporEnergyThreshold = torporEnergyThreshold
        self.permanentDeath = permanentDeath
    }

    public static let standard = SimulationConfiguration()

    public static let acceleratedTests = SimulationConfiguration(
        basalEnergyCostPerSecond: 0.02,
        walkingEnergyMultiplier: 2,
        flightEnergyMultiplier: 5,
        feedingEnergyPerSecond: 0.2,
        fatigueGainPerSecond: 0.04,
        restRecoveryPerSecond: 0.15,
        groomingRecoveryPerSecond: 0.4,
        naturalContaminationPerSecond: 0.02,
        torporEnergyThreshold: 0.03,
        permanentDeath: false
    )
}

