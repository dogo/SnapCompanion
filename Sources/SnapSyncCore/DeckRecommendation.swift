import Foundation

public struct DeckRecommendation: Sendable, Equatable, Identifiable {
    public let archetype: MetaArchetype
    public let cardDefinitionIDs: [String]
    public let missingCardDefinitionIDs: [String]

    public var id: String { "\(archetype.supertype)|\(archetype.name)" }
    public var ownedCardCount: Int { cardDefinitionIDs.count - missingCardDefinitionIDs.count }
    public var isComplete: Bool { missingCardDefinitionIDs.isEmpty }

    public static func ranked(
        ownedCardDefinitionIDs: [String],
        archetypes: [MetaArchetype]
    ) -> [Self] {
        let owned = Set(ownedCardDefinitionIDs)
        return archetypes.compactMap { archetype in
            let weights = Dictionary(archetype.cards.map { ($0.id, $0.weight) }, uniquingKeysWith: max)
            let cards = weights.sorted { lhs, rhs in
                lhs.value == rhs.value
                    ? lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
                    : lhs.value > rhs.value
            }
            .prefix(12)
            .map(\.key)
            guard cards.count == 12 else { return nil }
            return Self(
                archetype: archetype,
                cardDefinitionIDs: cards,
                missingCardDefinitionIDs: cards.filter { owned.contains($0) == false }
            )
        }
        .sorted { lhs, rhs in
            let lhsCoverage = Double(lhs.ownedCardCount) / Double(lhs.cardDefinitionIDs.count)
            let rhsCoverage = Double(rhs.ownedCardCount) / Double(rhs.cardDefinitionIDs.count)
            if lhsCoverage != rhsCoverage { return lhsCoverage > rhsCoverage }
            if lhs.archetype.decksCount != rhs.archetype.decksCount {
                return lhs.archetype.decksCount > rhs.archetype.decksCount
            }
            return lhs.archetype.name.localizedStandardCompare(rhs.archetype.name) == .orderedAscending
        }
    }
}
