import Foundation
import Testing

@testable import SnapSyncCore

// Messages shaped like the game's GetChangesResponse WebSocket payloads.
// Player 1 is me (me-123), player 2 the opponent (opp-999).
private func message(_ changes: String) -> Data {
    Data("""
    {"$type":"ChangeNotification","AccountId":"me-123","Changes":[\(changes)]}
    """.utf8)
}

private let setup = """
{"$type":"GameCreateChange","StartingCubeValue":1},
{"$type":"GameCreatePlayerChange","EntityId":1,"PlayerInfo":{"AccountId":"me-123","Name":"Me"}},
{"$type":"GameCreatePlayerChange","EntityId":2,"PlayerInfo":{"AccountId":"opp-999","Name":"Opp"}},
{"$type":"GameCreateCardChange","EntityId":10,"OwnerEntityId":2},
{"$type":"GameCreateCardChange","EntityId":11,"OwnerEntityId":2},
{"$type":"GameCreateCardChange","EntityId":12,"OwnerEntityId":2}
"""

@Test func excludesGeneratedCardsFromDeckCards() throws {
    let tracker = MatchTracker()
    _ = tracker.process(message(setup))
    let snapshot = try #require(tracker.process(message("""
    {"$type":"GameRevealCardChange","EntityId":10,"CardDefId":"Mobius","CreatedByCardDefId":null},
    {"$type":"GameRevealCardChange","EntityId":11,"CardDefId":"Hulk","CreatedByCardDefId":"Agent13"},
    {"$type":"GameRevealCardChange","EntityId":12,"CardDefId":"Rock","CreatedByLocationDefId":"Quarry"}
    """)))
    #expect(snapshot.opponentName == "Opp")
    #expect(snapshot.opponentCards == ["Mobius", "Hulk", "Rock"])
    #expect(snapshot.opponentDeckCards == ["Mobius"])
}

@Test func recordsWhoSnapped() throws {
    let tracker = MatchTracker()
    _ = tracker.process(message(setup))
    var snapshot = try #require(tracker.process(message("""
    {"$type":"GameRaiseStakesForNextTurnChange","PlayerEntityId":2,"CubeValueNextTurn":2}
    """)))
    #expect(snapshot.opponentSnapped && !snapshot.youSnapped)

    snapshot = try #require(tracker.process(message("""
    {"$type":"PlayerStakesRaisedChange","PlayerEntityId":1,"CubeValue":4,"TotalRaisedCount":2}
    """)))
    #expect(snapshot.opponentSnapped && snapshot.youSnapped)
    #expect(snapshot.snaps == 2)

    // The automatic final-turn doubling raises the cube but isn't a snap.
    snapshot = try #require(tracker.process(message("""
    {"$type":"GameStakesRaisedChange","CubeValue":8,"TotalRaisedCount":3}
    """)))
    #expect(snapshot.cubeValue == 8)
    #expect(snapshot.snaps == 2)

    // A new match clears it.
    snapshot = try #require(tracker.process(message(setup)))
    #expect(!snapshot.opponentSnapped && !snapshot.youSnapped)
}
