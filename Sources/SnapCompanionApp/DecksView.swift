import SnapSyncCore
import SwiftUI

struct DecksView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""
    @State private var showsRecommendations = false
    @State private var includesIncompleteDecks = true
    @State private var recommendations: [DeckRecommendation] = []
    @State private var isLoadingRecommendations = false
    @State private var recommendationsUnavailable = false
    @State private var selectedDeck: SnapSnapshot.Deck?
    @State private var selectedRecommendation: DeckRecommendation?
    private let columns = [GridItem(.adaptive(minimum: 270))]

    var body: some View {
        let decks = searchText.isEmpty
            ? model.decks
            : model.decks.filter { $0.name.localizedStandardContains(searchText) }
        let recommendationResults = recommendations.filter { recommendation in
            (includesIncompleteDecks || recommendation.isComplete)
                && (searchText.isEmpty
                    || recommendation.archetype.name.localizedStandardContains(searchText)
                    || recommendation.archetype.supertype.localizedStandardContains(searchText))
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DecksHeaderView(
                    title: showsRecommendations ? .deckRecommendations : .decksHeaderTitle,
                    subtitle: showsRecommendations ? .deckRecommendationsSubtitle : .decksHeaderSubtitle,
                    deckCount: showsRecommendations ? recommendations.count : model.deckCount
                )

                Picker(.sectionDecks, selection: $showsRecommendations) {
                    Text(.decksHeaderTitle).tag(false)
                    Text(.deckRecommendations).tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                if showsRecommendations {
                    Toggle(.includeIncompleteDecks, isOn: $includesIncompleteDecks)

                    if isLoadingRecommendations {
                        ProgressView(.loadingRecommendations)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if recommendationsUnavailable {
                        VStack {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(.recommendationsUnavailable)
                                .font(.title2)
                                .bold()
                            Button(action: retryRecommendations) {
                                Label(.retry, systemImage: "arrow.clockwise")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else if recommendationResults.isEmpty {
                        VStack {
                            Image(systemName: searchText.isEmpty ? "rectangle.stack.badge.questionmark" : "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(searchText.isEmpty ? .emptyNoCompleteRecommendations : .emptyNoResults)
                                .font(.title2)
                                .bold()
                            Text(searchText.isEmpty ? .emptyIncludeIncompleteDecks : .emptyTryAnotherDeckName)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        LazyVGrid(columns: columns) {
                            ForEach(recommendationResults) { recommendation in
                                Button {
                                    selectedRecommendation = recommendation
                                } label: {
                                    DeckPreviewCard(recommendation: recommendation)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(.recommendationAccessibility(
                                    recommendation.archetype.name,
                                    recommendation.ownedCardCount,
                                    recommendation.cardDefinitionIDs.count
                                )))
                                .accessibilityHint(Text(.openDeckAccessibilityHint))
                            }
                        }
                    }
                } else if decks.isEmpty {
                    VStack {
                        Image(systemName: searchText.isEmpty ? "rectangle.stack.badge.questionmark" : "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(model.decks.isEmpty ? .emptyNoDecks : .emptyNoResults)
                            .font(.title2)
                            .bold()
                        Text(model.decks.isEmpty ? .emptyValidFolderSettings : .emptyTryAnotherDeckName)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    LazyVGrid(columns: columns) {
                        ForEach(decks) { deck in
                            Button {
                                selectedDeck = deck
                            } label: {
                                DeckPreviewCard(deck: deck)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(.deckAccessibility(deck.name, deck.cardDefinitionIDs.count)))
                            .accessibilityHint(Text(.openDeckAccessibilityHint))
                        }
                    }
                }
            }
            .padding()
        }
        .background {
            LinearGradient(
                colors: [.blue.opacity(0.08), .purple.opacity(0.05), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .navigationTitle(Text(.sectionDecks))
        .searchable(text: $searchText, prompt: Text(.searchDeck))
        .sheet(item: $selectedDeck) { deck in
            DeckDetailView(deck: deck)
        }
        .sheet(item: $selectedRecommendation) { recommendation in
            DeckDetailView(recommendation: recommendation)
        }
        .task(id: model.collection.map(\.id)) {
            await loadRecommendations()
        }
    }

    private func loadRecommendations() async {
        isLoadingRecommendations = true
        recommendationsUnavailable = false
        defer { isLoadingRecommendations = false }
        do {
            recommendations = DeckRecommendation.ranked(
                ownedCardDefinitionIDs: model.collection.map(\.id),
                archetypes: try await MetaArchetypes.shared.archetypes()
            )
        } catch is CancellationError {
            return
        } catch {
            recommendationsUnavailable = recommendations.isEmpty
        }
    }

    private func retryRecommendations() {
        Task { await loadRecommendations() }
    }
}

private struct DecksHeaderView: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let deckCount: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 130))
                .foregroundStyle(.white.opacity(0.08))
                .offset(x: 28, y: -38)
                .accessibilityHidden(true)

            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.largeTitle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading) {
                    Text(title)
                        .font(.title)
                        .bold()
                    Text(subtitle)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(.deckCount(deckCount))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()
            }
            .padding()
        }
        .foregroundStyle(.white)
        .background {
            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(.rect(cornerRadius: 20))
        .shadow(color: .blue.opacity(0.22), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }
}

private struct DeckPreviewCard: View {
    let name: String
    let cardDefinitionIDs: [String]
    let status: String
    let statusSystemImage: String
    let statusColor: Color

    init(deck: SnapSnapshot.Deck) {
        name = deck.name
        cardDefinitionIDs = deck.cardDefinitionIDs
        status = String(localized: .cardCount(deck.cardDefinitionIDs.count))
        statusSystemImage = "rectangle.stack.fill"
        statusColor = .secondary
    }

    init(recommendation: DeckRecommendation) {
        name = recommendation.archetype.name
        cardDefinitionIDs = recommendation.cardDefinitionIDs
        status = String(localized: .recommendationProgress(
            recommendation.ownedCardCount,
            recommendation.cardDefinitionIDs.count
        ))
        statusSystemImage = recommendation.isComplete ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        statusColor = recommendation.isComplete ? .green : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if cardDefinitionIDs.isEmpty {
                Image(systemName: "rectangle.stack.badge.questionmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 92)
                    .accessibilityHidden(true)
            } else {
                HStack(spacing: -18) {
                    ForEach(Array(cardDefinitionIDs.prefix(4).enumerated()), id: \.offset) { index, definitionID in
                        CollectionCardImageView(definitionID: definitionID)
                            .frame(width: 78, height: 78)
                            .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
                            .zIndex(Double(index))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 92)
            }

            Text(name)
                .font(.headline)
                .lineLimit(2)

            Label(status, systemImage: statusSystemImage)
                .font(.subheadline)
                .foregroundStyle(statusColor)
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .shadow(color: .blue.opacity(0.1), radius: 8, y: 4)
        .contentShape(.rect(cornerRadius: 16))
    }
}

private struct DeckDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let name: String
    let cardDefinitionIDs: [String]
    let missingCardDefinitionIDs: Set<String>
    private let columns = [GridItem(.adaptive(minimum: 150))]

    init(deck: SnapSnapshot.Deck) {
        name = deck.name
        cardDefinitionIDs = deck.cardDefinitionIDs
        missingCardDefinitionIDs = []
    }

    init(recommendation: DeckRecommendation) {
        name = recommendation.archetype.name
        cardDefinitionIDs = recommendation.cardDefinitionIDs
        missingCardDefinitionIDs = Set(recommendation.missingCardDefinitionIDs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns) {
                    ForEach(cardDefinitionIDs, id: \.self) { definitionID in
                        VStack(alignment: .leading) {
                            CollectionCardImageView(definitionID: definitionID)
                            Text(displayName(for: definitionID))
                                .font(.headline)
                                .lineLimit(2)
                            if missingCardDefinitionIDs.contains(definitionID) {
                                Label(.missing, systemImage: "exclamationmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 16))
                        .overlay {
                            if missingCardDefinitionIDs.contains(definitionID) {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.orange, lineWidth: 2)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding()
            }
            .background {
                LinearGradient(
                    colors: [.purple.opacity(0.08), .blue.opacity(0.05), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .navigationTitle(name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: dismiss.callAsFunction) {
                        Text(.close)
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 620)
    }

    private func displayName(for definitionID: String) -> String {
        definitionID.replacing(/([a-z0-9])([A-Z])/) { match in
            "\(match.1) \(match.2)"
        }
    }
}
