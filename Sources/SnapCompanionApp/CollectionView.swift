import SnapSyncCore
import SwiftUI

struct CollectionView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""
    @State private var filter: CollectionFilter = .all
    @State private var sort: CollectionSort = .nameAscending
    @State private var catalog: [CardCatalogEntry] = []
    @State private var catalogUnavailable = false
    @State private var selectedCard: CollectionCard?
    private let columns = [GridItem(.adaptive(minimum: 200))]

    var body: some View {
        let collection = CollectionQuery.cards(owned: model.collection, catalog: catalog)
        let cards = CollectionQuery.results(
            in: collection,
            searchText: searchText,
            filter: filter,
            sort: sort
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CollectionHeaderView(
                    ownedCount: model.cardCount,
                    totalCount: catalog.isEmpty ? nil : collection.count,
                    variantCount: model.variantCount
                )

                if catalogUnavailable {
                    Label(.collectionCatalogUnavailable, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                }

                CollectionControlsView(filter: $filter, sort: $sort, resultCount: cards.count)

                if cards.isEmpty {
                    VStack {
                        Image(systemName: searchText.isEmpty ? "rectangle.stack.badge.questionmark" : "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(model.collection.isEmpty ? .emptyNoCards : .emptyNoResults)
                            .font(.title2)
                            .bold()
                        Text(model.collection.isEmpty ? .emptyValidFolderSettings : .emptyAdjustSearchFilters)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    LazyVGrid(columns: columns) {
                        ForEach(cards) { card in
                            Button {
                                selectedCard = card
                            } label: {
                                CollectionCardView(card: card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background {
            LinearGradient(
                colors: [.purple.opacity(0.07), .pink.opacity(0.04), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .navigationTitle(Text(.sectionCollection))
        .searchable(text: $searchText, prompt: Text(.searchCard))
        .sheet(item: $selectedCard) { card in
            CardDetailView(card: card)
        }
        .task { await loadCatalog() }
    }

    private func loadCatalog() async {
        do {
            catalog = try await CardCatalog.shared.entries()
            catalogUnavailable = false
        } catch is CancellationError {
            return
        } catch {
            catalogUnavailable = true
        }
    }
}
