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

            if model.matchTurn > 0 {
                Label {
                    Text(.overlayTurn(model.matchTurn, model.matchTotalTurns))
                } icon: {
                    Image(systemName: "hourglass")
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            if model.locations.isEmpty == false {
                HStack(spacing: 6) {
                    ForEach(Array(model.locations.enumerated()), id: \.offset) { _, id in
                        LocationImageView(definitionID: id, width: 108, height: 108)
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
            }
        }
        .padding(16)
        .frame(width: 400, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12)))
    }

    private let columns = [GridItem(.adaptive(minimum: 62), spacing: 8)]
}
