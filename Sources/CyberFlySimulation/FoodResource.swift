import CyberFlyCore
import Foundation

public enum FoodFreshnessPhase: String, Equatable, Sendable {
    case fresh
    case spoiling
    case gone

    public var displayName: String {
        switch self {
        case .fresh: "新鲜"
        case .spoiling: "正在腐败"
        case .gone: "已消失"
        }
    }
}

/// A finite piece of desktop food. Its original portion is never replenished:
/// feeding consumes it and wall-clock age eventually removes it.
public struct FoodResource: Equatable, Sendable {
    public static let defaultFreshDuration: TimeInterval = 8 * 60
    public static let defaultMaximumLifetime: TimeInterval = 12 * 60
    public static let defaultConsumptionPerSecond = 0.18

    public let id: UUID
    public let odorCue: FlyOdorCue
    public let positionX: Double
    public let positionY: Double
    public let placedAt: Date
    public let freshDuration: TimeInterval
    public let maximumLifetime: TimeInterval
    public private(set) var remainingPortion: Double

    public init(
        id: UUID = UUID(),
        odorCue: FlyOdorCue = .amber,
        positionX: Double,
        positionY: Double,
        placedAt: Date = Date(),
        freshDuration: TimeInterval = FoodResource.defaultFreshDuration,
        maximumLifetime: TimeInterval = FoodResource.defaultMaximumLifetime,
        remainingPortion: Double = 1
    ) {
        self.id = id
        self.odorCue = odorCue
        self.positionX = Self.clamp(positionX)
        self.positionY = Self.clamp(positionY)
        self.placedAt = placedAt
        self.freshDuration = max(freshDuration, 0)
        self.maximumLifetime = max(maximumLifetime, max(freshDuration, 0) + 0.001)
        self.remainingPortion = Self.clamp(remainingPortion)
    }

    public func age(at now: Date = Date()) -> TimeInterval {
        max(now.timeIntervalSince(placedAt), 0)
    }

    public func phase(at now: Date = Date()) -> FoodFreshnessPhase {
        guard isAvailable(at: now) else { return .gone }
        return age(at: now) < freshDuration ? .fresh : .spoiling
    }

    public func freshness(at now: Date = Date()) -> Double {
        guard remainingPortion > 0.0001 else { return 0 }
        let currentAge = age(at: now)
        guard currentAge < maximumLifetime else { return 0 }
        guard currentAge > freshDuration else { return 1 }
        return Self.clamp(
            1 - (currentAge - freshDuration) / (maximumLifetime - freshDuration)
        )
    }

    public func isAvailable(at now: Date = Date()) -> Bool {
        remainingPortion > 0.0001 && age(at: now) < maximumLifetime
    }

    public func odorStrength(at now: Date = Date()) -> Double {
        guard isAvailable(at: now) else { return 0 }
        let freshnessFactor = 0.35 + freshness(at: now) * 0.65
        return Self.clamp(sqrt(remainingPortion) * freshnessFactor)
    }

    public func edibleStrength(at now: Date = Date()) -> Double {
        guard isAvailable(at: now) else { return 0 }
        return Self.clamp(sqrt(remainingPortion) * freshness(at: now))
    }

    /// Returns true when the food has been completely consumed.
    @discardableResult
    public mutating func consume(
        deltaTime: TimeInterval,
        contactStrength: Double,
        ratePerSecond: Double = FoodResource.defaultConsumptionPerSecond
    ) -> Bool {
        let consumed = max(deltaTime, 0)
            * Self.clamp(contactStrength)
            * max(ratePerSecond, 0)
        remainingPortion = Self.clamp(remainingPortion - consumed)
        return remainingPortion <= 0.0001
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
