import Foundation
import Testing
@testable import SnapSyncCore

// Minimal GameState.json shaped like the real file (RemoteGame.GameState +
// ClientPlayerInfo), covering cube, snaps and the end-of-match result.
private func gameState(cube: Int, stakes: Int, resultItems: String?) -> Data {
    let crm = resultItems.map {
        """
        ,"ClientResultMessage":{"FinalCubeValue":\(cube),"GameResultAccountItems":[\($0)]}
        """
    } ?? ""
    return Data("""
    {"RemoteGame":{
      "ClientPlayerInfo":{"AccountId":"me-123","CardsPlayed":["Agony","None"],"CardsDrawn":["Magik"]},
      "GameState":{"Turn":7,"TotalTurns":7,"CubeValue":\(cube),"StakesRaisedCount":\(stakes)\(crm)}
    }}
    """.utf8)
}

@Test func noResultUntilMatchEnds() {
    let state = MatchState.parse(gameState(cube: 4, stakes: 2, resultItems: nil))
    #expect(state?.cubeValue == 4)
    #expect(state?.result == nil)   // no ClientResultMessage yet
}

@Test func parsesWinResultMatchedToMyAccount() {
    let items = """
    {"AccountId":"opp-999","IsWinner":false},
    {"AccountId":"me-123","IsWinner":true,"FinalCubeValue":8,"CurrencyRewardEarned":8}
    """
    let state = MatchState.parse(gameState(cube: 8, stakes: 3, resultItems: items))
    #expect(state?.result == MatchResult(didWin: true, cubes: 8))
}

@Test func parsesLossMatchedToMyAccount() {
    let items = """
    {"AccountId":"me-123","IsWinner":false},
    {"AccountId":"opp-999","IsWinner":true}
    """
    let state = MatchState.parse(gameState(cube: 2, stakes: 0, resultItems: items))
    #expect(state?.result?.didWin == false)
    #expect(state?.result?.cubes == 2)
}
