import SnapSyncCore
import SwiftUI

struct OverviewView: View {
    @ObservedObject var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 150))]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SyncStatusCard(model: model)

                LazyVGrid(columns: columns) {
                    MetricCard(
                        title: .metricCards,
                        value: model.cardCount.formatted(),
                        systemImage: "rectangle.stack.fill",
                        tint: .purple
                    )
                    MetricCard(
                        title: .metricVariants,
                        value: model.variantCount.formatted(),
                        systemImage: "sparkles.rectangle.stack",
                        tint: .pink
                    )
                    MetricCard(
                        title: .metricDecks,
                        value: model.deckCount.formatted(),
                        systemImage: "square.stack.3d.up.fill",
                        tint: .blue
                    )
                    MetricCard(
                        title: .metricCollectionLevel,
                        value: model.collectionLevel?.formatted() ?? "—",
                        systemImage: "chart.line.uptrend.xyaxis",
                        tint: .orange
                    )
                }

                if let best = model.sessionStats.decks(by: .cubes).first {
                    bestDeckCard(best)
                }
                InventorySummaryView(model: model)
                SnapshotChangesView(change: model.lastChange)
            }
            .padding()
        }
        .background {
            LinearGradient(
                colors: [.purple.opacity(0.08), .blue.opacity(0.04), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .navigationTitle(Text(.sectionOverview))
    }

    private func bestDeckCard(_ stat: DeckStat) -> some View {
        HStack {
            Label { Text(.overviewBestDeck) } icon: { Image(systemName: "trophy.fill") }
                .foregroundStyle(.yellow)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(stat.deck).font(.headline).lineLimit(1)
                Text(verbatim: "\(stat.cubes >= 0 ? "+" : "−")\(abs(stat.cubes)) · \(stat.wins)–\(stat.losses)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}
