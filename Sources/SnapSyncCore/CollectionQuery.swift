import Foundation

public enum CollectionFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case owned
    case missing
    case withVariants
    case withBoosters
    case withoutBoosters

    public var id: Self { self }
}

public enum CollectionSort: String, CaseIterable, Identifiable, Sendable {
    case nameAscending
    case nameDescending
    case mostVariants
    case mostBoosters

    public var id: Self { self }
}

public enum CollectionQuery {
    public static func cards(
        owned: [SnapSnapshot.OwnedCard],
        catalog: [CardCatalogEntry]
    ) -> [CollectionCard] {
        let ownedByID = Dictionary(uniqueKeysWithValues: owned.map { ($0.id, $0) })
        let catalogIDs = Set(catalog.map(\.id))
        return (
            catalog.map { CollectionCard(id: $0.id, name: $0.name, ownedCard: ownedByID[$0.id], cost: $0.cost, power: $0.power, text: $0.text) }
                + owned.filter { catalogIDs.contains($0.id) == false }.map {
                    CollectionCard(id: $0.id, name: displayName(for: $0.id), ownedCard: $0)
                }
        )
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func results(
        in cards: [CollectionCard],
        searchText: String,
        filter: CollectionFilter,
        sort: CollectionSort
    ) -> [CollectionCard] {
        let query = searchText.replacing(" ", with: "")
        return cards
            .filter { card in
                (query.isEmpty
                    || card.id.localizedStandardContains(query)
                    || card.name.replacing(" ", with: "").localizedStandardContains(query))
                    && filter.includes(card)
            }
            .sorted { sort.precedes($0, $1) }
    }

    private static func displayName(for definitionID: String) -> String {
        definitionID.replacing(/([a-z0-9])([A-Z])/) { match in
            "\(match.1) \(match.2)"
        }
    }
}

private extension CollectionFilter {
    func includes(_ card: CollectionCard) -> Bool {
        switch self {
        case .all: true
        case .owned: card.isOwned
        case .missing: card.isOwned == false
        case .withVariants: card.isOwned && card.variants.count > 1
        case .withBoosters: card.isOwned && (card.boosters ?? 0) > 0
        case .withoutBoosters: card.isOwned && (card.boosters ?? 0) == 0
        }
    }
}

private extension CollectionSort {
    func precedes(_ lhs: CollectionCard, _ rhs: CollectionCard) -> Bool {
        switch self {
        case .nameAscending:
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .nameDescending:
            lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
        case .mostVariants:
            lhs.variants.count == rhs.variants.count
                ? CollectionSort.nameAscending.precedes(lhs, rhs)
                : lhs.variants.count > rhs.variants.count
        case .mostBoosters:
            (lhs.boosters ?? 0) == (rhs.boosters ?? 0)
                ? CollectionSort.nameAscending.precedes(lhs, rhs)
                : (lhs.boosters ?? 0) > (rhs.boosters ?? 0)
        }
    }
}
