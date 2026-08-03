import SnapSyncCore
import SwiftUI

struct SessionStatsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmingReset = false

    var body: some View {
        let stats = model.sessionStats
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.statsTitle).font(.largeTitle.bold())
                        Text(.statsSubtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !stats.isEmpty {
                        Button(role: .destructive) { confirmingReset = true } label: {
                            Label { Text(.statsReset) } icon: { Image(systemName: "trash") }
                        }
                        .confirmationDialog(Text(.statsResetPrompt), isPresented: $confirmingReset) {
                            Button(role: .destructive) { model.resetStats() } label: { Text(.statsReset) }
                        }
                    }
                }

                if stats.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.largeTitle).foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(.statsEmpty).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                        GridRow {
                            Text(.statsColDeck)
                            Text(.statsColRecord).gridColumnAlignment(.trailing)
                            Text(.statsColWinRate).gridColumnAlignment(.trailing)
                            Text(.statsColCubes).gridColumnAlignment(.trailing)
                        }
                        .font(.caption.bold()).foregroundStyle(.secondary)

                        Divider().gridCellColumns(4)

                        ForEach(stats.decks) { row(for: $0) }

                        Divider().gridCellColumns(4)
                        GridRow {
                            Text(.statsTotal).bold()
                            Text(verbatim: "\(stats.totalWins)–\(stats.totalGames - stats.totalWins)")
                            Text(verbatim: percent(stats.totalWins, stats.totalGames))
                            cubes(stats.totalCubes).bold()
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(for stat: DeckStat) -> some View {
        GridRow {
            Text(stat.deck).lineLimit(1)
            Text(verbatim: "\(stat.wins)–\(stat.losses)")
            Text(verbatim: "\(Int((stat.winRate * 100).rounded()))%")
            cubes(stat.cubes)
        }
    }

    private func cubes(_ n: Int) -> Text {
        Text(verbatim: n >= 0 ? "+\(n)" : "−\(-n)")
            .foregroundColor(n >= 0 ? .green : .red)
    }

    private func percent(_ wins: Int, _ games: Int) -> String {
        games == 0 ? "0%" : "\(Int((Double(wins) / Double(games) * 100).rounded()))%"
    }
}
