import SnapSyncCore
import SwiftUI

struct SessionStatsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmingReset = false
    @State private var sort: SessionStats.Sort = .games

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
                            header(.statsColDeck, .name)
                            header(.statsColRecord, .games).gridColumnAlignment(.trailing)
                            header(.statsColWinRate, .winRate).gridColumnAlignment(.trailing)
                            header(.statsColCubes, .cubes).gridColumnAlignment(.trailing)
                        }
                        .font(.caption.bold()).foregroundStyle(.secondary)

                        Divider().gridCellColumns(4)

                        ForEach(stats.decks(by: sort)) { row(for: $0) }

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

    private func header(_ title: LocalizedStringResource, _ key: SessionStats.Sort) -> some View {
        Button { sort = key } label: {
            HStack(spacing: 2) {
                Text(title)
                if sort == key { Image(systemName: "chevron.down").font(.caption2) }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(sort == key ? Color.primary : .secondary)
    }

    private func row(for stat: DeckStat) -> some View {
        GridRow {
            Text(stat.deck).lineLimit(1)
            Text(verbatim: "\(stat.wins)–\(stat.losses)")
            winRateBar(stat.winRate)
            cubes(stat.cubes)
        }
    }

    private func winRateBar(_ rate: Double) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(.quaternary)
                .frame(width: 40, height: 5)
                .overlay(alignment: .leading) {
                    Capsule().fill(.green).frame(width: 40 * rate, height: 5)
                }
            Text(verbatim: "\(Int((rate * 100).rounded()))%")
                .monospacedDigit()
        }
        .accessibilityElement()
        .accessibilityLabel(Text(.statsColWinRate))
        .accessibilityValue(Text(verbatim: "\(Int((rate * 100).rounded()))%"))
    }

    private func cubes(_ n: Int) -> Text {
        Text(verbatim: n >= 0 ? "+\(n)" : "−\(-n)")
            .foregroundColor(n >= 0 ? .green : .red)
    }

    private func percent(_ wins: Int, _ games: Int) -> String {
        games == 0 ? "0%" : "\(Int((Double(wins) / Double(games) * 100).rounded()))%"
    }
}
