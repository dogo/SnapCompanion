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

@Test func reportsLocationPowerFromMySideOnceCalibrated() throws {
    let tracker = MatchTracker()
    _ = tracker.process(message(setup + """
    ,{"$type":"GameCreateLocationChange","EntityId":20,"LocationDefId":"Ruins","Player1Power":0,"Player2Power":0},
    {"$type":"GameCreateLocationChange","EntityId":21,"LocationDefId":"Utopia","Player1Power":0,"Player2Power":0}
    """))
    // A tie names no winner, so which side is ours is still unknown.
    var snapshot = try #require(tracker.process(message("""
    {"$type":"LocationPowerTotalsChange","EntityId":20,"Player1Power":3,"Player2Power":3}
    """)))
    #expect(snapshot.locationPowers.isEmpty)

    // Opponent (entity 2) leads with Player1Power, so we are Player2.
    snapshot = try #require(tracker.process(message("""
    {"$type":"LocationPowerTotalsChange","EntityId":21,"Player1Power":7,"Player2Power":2,"WinnerEntityId":2}
    """)))
    #expect(snapshot.locationPowers == [[3, 3], [2, 7]])
}

@Test func calibratesWhenIAmPlayerOne() throws {
    let tracker = MatchTracker()
    _ = tracker.process(message(setup + """
    ,{"$type":"GameCreateLocationChange","EntityId":20,"LocationDefId":"Ruins","Player1Power":0,"Player2Power":0}
    """))
    let snapshot = try #require(tracker.process(message("""
    {"$type":"LocationPowerTotalsChange","EntityId":20,"Player1Power":5,"Player2Power":1,"WinnerEntityId":1}
    """)))
    #expect(snapshot.locationPowers == [[5, 1]])

    // Zero powers are omitted on the wire; a missing field is 0, not "no update".
    let zeroed = try #require(tracker.process(message("""
    {"$type":"LocationPowerTotalsChange","EntityId":20,"Player1Power":9}
    """)))
    #expect(zeroed.locationPowers == [[9, 0]])
}

@Test func trimsOpponentName() throws {
    let tracker = MatchTracker()
    let snapshot = try #require(tracker.process(message("""
    {"$type":"GameCreateChange","StartingCubeValue":1},
    {"$type":"GameCreatePlayerChange","EntityId":1,"PlayerInfo":{"AccountId":"me-123","Name":"Me"}},
    {"$type":"GameCreatePlayerChange","EntityId":2,"PlayerInfo":{"AccountId":"opp-999","Name":"Random "}}
    """)))
    #expect(snapshot.opponentName == "Random")
}

@Test func reportsResultFromGameResultChange() throws {
    let tracker = MatchTracker()
    _ = tracker.process(message(setup))
    let snapshot = try #require(tracker.process(message("""
    {"$type":"GameResultChange","Message":{"GameId":"g-1","FinalCubeValue":4,"GameResultAccountItems":[
      {"AccountId":"me-123","IsWinner":true,"OpponentConceded":true,"Deck":{"Name":"Death Knull"}}]}}
    """)))
    let expected = MatchResult(didWin: true, cubes: 4, deck: "Death Knull", gameId: "g-1", retreat: .opponent)
    #expect(snapshot.result == expected)

    // Survives the trip through the live-match JSON the app reads.
    let json = try #require(snapshot.json)
    let obj = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
    let roundTrip = try JSONSerialization.data(withJSONObject: try #require(obj["result"]))
    #expect(try JSONDecoder().decode(MatchResult.self, from: roundTrip) == expected)

    // A new match clears it.
    #expect(try #require(tracker.process(message(setup))).result == nil)
}

@Test func readsResultMessageSentAsJSONText() throws {
    let tracker = MatchTracker()
    _ = tracker.process(message(setup))
    let inner = #"{\"GameId\":\"g-2\",\"FinalCubeValue\":1,\"GameResultAccountItems\":[{\"AccountId\":\"me-123\",\"IsLoser\":true,\"Conceded\":true}]}"#
    let snapshot = try #require(tracker.process(message("""
    {"$type":"GameResultChange","Message":"\(inner)"}
    """)))
    #expect(snapshot.result?.didWin == false)
    #expect(snapshot.result?.retreat == .you)
}

@Test func countsOpponentHandDeckAndRevealedGraveyard() throws {
    let tracker = MatchTracker()
    _ = tracker.process(message("""
    {"$type":"GameCreateChange","StartingCubeValue":1},
    {"$type":"GameCreatePlayerChange","EntityId":1,"PlayerInfo":{"AccountId":"me-123","Name":"Me"},
     "DeckEntityId":101,"HandEntityId":102,"GraveyardEntityId":103},
    {"$type":"GameCreatePlayerChange","EntityId":2,"PlayerInfo":{"AccountId":"opp-999","Name":"Opp"},
     "DeckEntityId":201,"HandEntityId":202,"GraveyardEntityId":203},
    {"$type":"GameCreateCardChange","EntityId":10,"OwnerEntityId":2,"ZoneEntityId":201},
    {"$type":"GameCreateCardChange","EntityId":11,"OwnerEntityId":2,"ZoneEntityId":201},
    {"$type":"GameCreateCardChange","EntityId":12,"OwnerEntityId":2,"ZoneEntityId":201},
    {"$type":"GameCreateCardChange","EntityId":13,"OwnerEntityId":1,"ZoneEntityId":101}
    """))
    // Opponent draws two; one is played (revealed at a location) and later destroyed.
    let snapshot = try #require(tracker.process(message("""
    {"$type":"CardMoveChange","CardEntityId":10,"TargetZoneEntityId":202},
    {"$type":"CardMoveChange","CardEntityId":11,"TargetZoneEntityId":202},
    {"$type":"CardMoveChange","CardEntityId":11,"TargetZoneEntityId":20},
    {"$type":"GameRevealCardChange","EntityId":11,"CardDefId":"Nova"},
    {"$type":"CardMoveChange","CardEntityId":11,"TargetZoneEntityId":203}
    """)))
    #expect(snapshot.opponentHandCount == 1)
    #expect(snapshot.opponentDeckCount == 1)
    #expect(snapshot.opponentGraveyard == ["Nova"])
}

@Test func readsOpponentProfileNumbersBareOrWrapped() throws {
    let tracker = MatchTracker()
    let snapshot = try #require(tracker.process(message("""
    {"$type":"GameCreateChange","StartingCubeValue":1},
    {"$type":"GameCreatePlayerChange","EntityId":1,"PlayerInfo":{"AccountId":"me-123","Name":"Me","HighWatermarkRank":90}},
    {"$type":"GameCreatePlayerChange","EntityId":2,"PlayerInfo":{"AccountId":"opp-999","Name":"Opp",
     "HighWatermarkRank":70,"CollectionScore":{"Amount":4200}}}
    """)))
    #expect(snapshot.opponentRank == 70)
    #expect(snapshot.opponentCollectionLevel == 4200)
}

@Test func dropsDestroyedLocation() throws {
    let tracker = MatchTracker()
    _ = tracker.process(message(setup + """
    ,{"$type":"GameCreateLocationChange","EntityId":20,"LocationDefId":"Ruins"},
    {"$type":"GameCreateLocationChange","EntityId":21,"LocationDefId":"Utopia"}
    """))
    let snapshot = try #require(tracker.process(message("""
    {"$type":"GameDestroyLocationChange","EntityId":20}
    """)))
    #expect(snapshot.locations == ["Utopia"])
}
