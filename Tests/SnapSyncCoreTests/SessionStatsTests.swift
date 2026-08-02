import Foundation
import Testing

@testable import SnapSyncCore

@Test func aggregatesWinsLossesAndNetCubesPerDeck() {
    var stats = SessionStats()
    stats.record(MatchResult(didWin: true, cubes: 8, deck: "Hela", gameId: "g1"))
    stats.record(MatchResult(didWin: false, cubes: 4, deck: "Hela", gameId: "g2"))
    stats.record(MatchResult(didWin: true, cubes: 2, deck: "Cerebro", gameId: "g3"))

    let hela = stats.decks.first { $0.deck == "Hela" }
    #expect(hela?.games == 2)
    #expect(hela?.wins == 1)
    #expect(hela?.losses == 1)
    #expect(hela?.cubes == 4)          // +8 − 4
    #expect(hela?.winRate == 0.5)

    #expect(stats.totalGames == 3)
    #expect(stats.totalCubes == 6)     // +8 −4 +2
    #expect(stats.decks.first?.deck == "Hela")  // most played first
}

@Test func recordsEachGameOnce() {
    var stats = SessionStats()
    #expect(stats.record(MatchResult(didWin: true, cubes: 8, deck: "Hela", gameId: "g1")) == true)
    #expect(stats.record(MatchResult(didWin: true, cubes: 8, deck: "Hela", gameId: "g1")) == false)
    #expect(stats.totalGames == 1)
}

@Test func ignoresResultsWithoutGameId() {
    var stats = SessionStats()
    #expect(stats.record(MatchResult(didWin: true, cubes: 8, deck: "Hela", gameId: "")) == false)
    #expect(stats.isEmpty)
}

@Test func parsesDeckAndGameIdFromResult() {
    let items = """
    {"AccountId":"me-123","IsWinner":true,"FinalCubeValue":8,"Deck":{"Name":"Wakanda Protocol"}}
    """
    let json = Data("""
    {"RemoteGame":{
      "ClientPlayerInfo":{"AccountId":"me-123"},
      "GameState":{"CubeValue":8,"ClientResultMessage":{"GameId":"abc-123","FinalCubeValue":8,"GameResultAccountItems":[\(items)]}}
    }}
    """.utf8)
    let result = MatchState.parse(json)?.result
    #expect(result?.deck == "Wakanda Protocol")
    #expect(result?.gameId == "abc-123")
    #expect(result?.didWin == true)
}
