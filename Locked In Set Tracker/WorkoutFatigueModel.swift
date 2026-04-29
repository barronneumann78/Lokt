import Foundation

struct FatigueAdjustedWeightSuggestion {
    let baseWeight: Double
    let suggestedWeight: Double
    let orderIndex: Int
    let fatiguePercent: Double
}

enum WorkoutFatigueModel {
    static let reductionPerPosition = 2.5
    static let maximumReduction = 12.0

    static func suggestion(baseWeight: Double, orderIndex: Int) -> FatigueAdjustedWeightSuggestion {
        let fatiguePercent = min(Double(orderIndex) * reductionPerPosition, maximumReduction)
        let multiplier = max(0, 1 - (fatiguePercent / 100))
        let suggestedWeight = baseWeight * multiplier

        return FatigueAdjustedWeightSuggestion(
            baseWeight: baseWeight,
            suggestedWeight: suggestedWeight,
            orderIndex: orderIndex,
            fatiguePercent: fatiguePercent
        )
    }
}
