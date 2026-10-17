import SnapSyncCore
import SwiftUI

struct MatchOverlayView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: model.botStatus == .human ? "person.fill" : "cpu")
                    .foregroundStyle(model.botStatus == .human ? Color.primary : Color.orange)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.opponentName.isEmpty ? String(localized: .overlayOpponent) : model.opponentName)
                        .font(.title3.bold())
                    if model.botStatus != .human {
                        Text(model.botStatus == .lstmBot ? .overlayBotLSTM : .overlayBotPossible)
                            .font(.caption2).bold()
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button {
                    model.toggleOverlay()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(.overlayHide))
            }

            if let result = model.liveResult ?? model.match?.result {
                HStack(spacing: 8) {
                    Image(systemName: result.didWin ? "trophy.fill" : "xmark.seal.fill")
                    Text(result.didWin ? .overlayWon(result.cubes) : .overlayLost(result.cubes))
                        .font(.subheadline.bold())
                    Spacer()
                    if result.retreat == .you {
                        Text(.overlayYouRetreated).font(.caption)
                    } else if result.retreat == .opponent {
                        Text(.overlayOpponentRetreated).font(.caption)
                    }
                    if result.vsBot {
                        Image(systemName: "cpu").accessibilityLabel(Text(.overlayVsBot))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(result.didWin ? Color.green.opacity(0.85) : Color.red.opacity(0.85),
                            in: .rect(cornerRadius: 10))
            }

            HStack(spacing: 12) {
                if model.matchTurn > 0 {
                    Label {
                        Text(.overlayTurn(model.matchTurn, model.matchTotalTurns))
                    } icon: {
                        Image(systemName: "hourglass")
                    }
                }
                if model.matchCubeValue > 0 {
                    Label {
                        Text("\(model.matchCubeValue)")
                    } icon: {
                        Image(systemName: "cube.fill")
                    }
                }
                if model.matchSnaps > 0 {
                    Label {
                        if model.youSnapped && model.opponentSnapped {
                            Text(.overlaySnapsBoth(model.matchSnaps))
                        } else if model.opponentSnapped {
                            Text(.overlaySnapsOpponent(model.matchSnaps))
                        } else if model.youSnapped {
                            Text(.overlaySnapsYou(model.matchSnaps))
                        } else {
                            Text(.overlaySnaps(model.matchSnaps))
                        }
                    } icon: {
                        Image(systemName: "flame.fill")
                    }
                    .foregroundStyle(.orange)
                }
            }
            .font(.caption).foregroundStyle(.secondary)

            if model.locations.isEmpty == false {
                HStack(spacing: 6) {
                    ForEach(Array(model.locations.enumerated()), id: \.offset) { index, id in
                        VStack(spacing: 2) {
                            LocationImageView(definitionID: id, width: 108, height: 108)
                            if model.locationPowers.indices.contains(index) {
                                powerLabel(model.locationPowers[index])
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if model.opponentCards.isEmpty {
                Text(.overlayWaiting)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(.overlayRevealed(model.opponentCards.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(model.opponentCards.enumerated()), id: \.offset) { _, id in
                        CollectionCardImageView(definitionID: id)
                            .frame(width: 62, height: 62)
                    }
                }
            }

            if let top = model.deckPredictions.first {
                Divider()
                ForEach(Array(model.deckPredictions.prefix(3).enumerated()), id: \.offset) { index, prediction in
                    HStack {
                        Text(index == 0 ? String(localized: .overlayLikely(prediction.archetype.name)) : prediction.archetype.name)
                            .font(index == 0 ? .subheadline.bold() : .caption)
                            .foregroundStyle(index == 0 ? .primary : .secondary)
                        Spacer()
                        Text("\(Int((prediction.confidence * 100).rounded()))%")
                            .font(.caption).bold()
                            .foregroundStyle(index == 0 ? (top.confidence >= 0.5 ? .green : .orange) : .secondary)
                    }
                }
                if top.remaining.isEmpty == false {
                    Text(.overlayWatchFor)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(top.remaining.prefix(8).enumerated()), id: \.offset) { _, id in
                            CollectionCardImageView(definitionID: id)
                                .frame(width: 62, height: 62)
                                .opacity(0.85)
                        }
                    }
                }
            } else if model.opponentDeckCards.isEmpty == false {
                Divider()
                Text(.overlayNoMetaMatch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let date = staleMetaDate, model.opponentDeckCards.isEmpty == false {
                Label {
                    Text(.overlayStaleMeta(date.formatted(date: .abbreviated, time: .omitted)))
                } icon: {
                    Image(systemName: "clock.badge.exclamationmark")
                }
                .font(.caption2)
                .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(width: 400, alignment: .leading)
        .background(WindowDragArea())
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12)))
    }

    /// "you – opponent", green when you're winning the location, red when losing.
    private func powerLabel(_ power: [Int]) -> some View {
        let (you, opponent) = (power.first ?? 0, power.last ?? 0)
        return Text(verbatim: "\(you) – \(opponent)")
            .font(.caption.bold()).monospacedDigit()
            .foregroundStyle(you > opponent ? .green : you < opponent ? .red : .secondary)
    }

    /// Meta older than two days means MarvelSnap.pro refreshes have been failing.
    private var staleMetaDate: Date? {
        model.metaFetchedAt.flatMap { $0 < .now.addingTimeInterval(-2 * 86_400) ? $0 : nil }
    }

    private let columns = [GridItem(.adaptive(minimum: 62), spacing: 8)]
}
