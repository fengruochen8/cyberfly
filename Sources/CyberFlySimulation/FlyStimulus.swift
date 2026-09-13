public struct FlyStimulus: Equatable, Sendable {
    public var foodOdor: Double
    public var foodContact: Double
    public var foodBearingRadians: Double?
    public var amberOdor: Double
    public var berryOdor: Double
    public var threat: Double
    public var threatBearingRadians: Double?
    public var visualMotionBearingRadians: Double?
    public var touch: Double
    public var novelty: Double
    public var contamination: Double
    public var sensorReliability: Double
    public var otherAgentID: String?
    public var otherAgentPresence: Double
    public var otherAgentMotion: Double
    public var otherAgentContingency: Double
    public var otherAgentThreat: Double

    public init(
        foodOdor: Double = 0,
        foodContact: Double = 0,
        foodBearingRadians: Double? = nil,
        amberOdor: Double = 0,
        berryOdor: Double = 0,
        threat: Double = 0,
        threatBearingRadians: Double? = nil,
        visualMotionBearingRadians: Double? = nil,
        touch: Double = 0,
        novelty: Double = 0,
        contamination: Double = 0,
        sensorReliability: Double = 1,
        otherAgentID: String? = nil,
        otherAgentPresence: Double = 0,
        otherAgentMotion: Double = 0,
        otherAgentContingency: Double = 0,
        otherAgentThreat: Double = 0
    ) {
        self.foodOdor = Self.clamp(foodOdor)
        self.foodContact = Self.clamp(foodContact)
        self.foodBearingRadians = foodBearingRadians
        self.amberOdor = Self.clamp(amberOdor)
        self.berryOdor = Self.clamp(berryOdor)
        self.threat = Self.clamp(threat)
        self.threatBearingRadians = threatBearingRadians
        self.visualMotionBearingRadians = visualMotionBearingRadians
        self.touch = Self.clamp(touch)
        self.novelty = Self.clamp(novelty)
        self.contamination = Self.clamp(contamination)
        self.sensorReliability = Self.clamp(sensorReliability)
        self.otherAgentID = otherAgentID
        self.otherAgentPresence = Self.clamp(otherAgentPresence)
        self.otherAgentMotion = Self.clamp(otherAgentMotion)
        self.otherAgentContingency = Self.clamp(otherAgentContingency)
        self.otherAgentThreat = Self.clamp(otherAgentThreat)
    }

    public static let quiet = FlyStimulus()

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
