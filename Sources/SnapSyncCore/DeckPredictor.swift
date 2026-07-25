import Foundation

/// A MarvelSnap.pro meta archetype: a weighted card composition.
public struct MetaArchetype: Codable, Sendable, Equatable {
    public let name: String
    public let supertype: String
    public let decksCount: Int
    public let cards: [Card]

    public struct Card: Codable, Sendable, Equatable {
        public let id: String
        public let weight: Double
        public init(id: String, weight: Double) { self.id = id; self.weight = weight }
    }

    public init(name: String, supertype: String, decksCount: Int, cards: [Card]) {
        self.name = name
        self.supertype = supertype
        self.decksCount = decksCount
        self.cards = cards
    }
}

public struct DeckPrediction: Sendable, Equatable {
    public let archetype: MetaArchetype
    public let matched: [String]     // revealed cards that belong to this archetype
    public let remaining: [String]   // likely-still-in-deck cards, most probable first
    public let confidence: Double    // 0...1, share of total evidence held by this archetype
}

/// Ranks archetypes by weighted evidence from the opponent's revealed cards and
/// how confident that ranking is. A revealed card counts more when it's rare
/// across archetypes (discriminative) and central to the archetype (high weight).
/// Confidence is each candidate's share of the evidence among the returned
/// candidates, so the leader reads how much it dominates the plausible field
/// rather than being diluted by every weakly-matching deck. Port + refinement
/// of spike/predict.py.
public enum DeckPredictor {
    public static func predict(revealed: [String], archetypes: [MetaArchetype], top: Int = 3) -> [DeckPrediction] {
        let revealedSet = Set(revealed)
        // How many archetypes each card appears in (rarer = more discriminative).
        var archetypeCount: [String: Int] = [:]
        for archetype in archetypes {
            for card in Set(archetype.cards.map(\.id)) { archetypeCount[card, default: 0] += 1 }
        }
        // Only cards that appear in some archetype — drops generated tokens.
        let real = revealedSet.filter { archetypeCount[$0] != nil }

        var scored: [(evidence: Double, pred: DeckPrediction)] = []
        for archetype in archetypes {
            let weights = Dictionary(archetype.cards.map { ($0.id, $0.weight) }, uniquingKeysWith: max)
            let matched = real.filter { weights[$0] != nil }
            guard !matched.isEmpty else { continue }
            let evidence = matched.reduce(0.0) { sum, card in
                sum + (weights[card] ?? 0) / Double(archetypeCount[card] ?? 1)
            }
            let remaining = archetype.cards
                .filter { !revealedSet.contains($0.id) }
                .sorted { $0.weight > $1.weight }
                .map(\.id)
            scored.append((evidence, DeckPrediction(
                archetype: archetype, matched: matched.sorted(), remaining: remaining, confidence: 0
            )))
        }

        let candidates = scored.sorted { $0.evidence > $1.evidence }.prefix(top)
        let total = candidates.reduce(0.0) { $0 + $1.evidence }
        return candidates.map { entry in
            DeckPrediction(
                archetype: entry.pred.archetype,
                matched: entry.pred.matched,
                remaining: entry.pred.remaining,
                confidence: total > 0 ? entry.evidence / total : 0
            )
        }
    }
}
