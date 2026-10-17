import Foundation
import Testing

@testable import SnapSyncCore

@Test func captureRetainsStructureWithoutScalarSecrets() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let capture = try NetworkMessageCapture(directory: directory, expiresAt: Date().addingTimeInterval(60), ownerID: getuid())
    capture.record(Data(#"{"$type":"CubeGame.GetChangesResponse, CubeGame","Token":"secret-token","AccountId":"secret-account","Code":123456,"Active":true,"Missing":null,"Changes":[{"$type":"PlayerEnergyChange","Energy":3}],"Message":"{\"Password\":\"nested-secret\"}","aabbccdd-1234-5678-9999-aabbccddeeff":"private"}"#.utf8),
                   direction: "server-to-client", connection: "test-connection")
    capture.finish()
    let data = try Data(contentsOf: capture.url)
    let text = String(decoding: data, as: UTF8.self)
    for secret in ["secret-token", "secret-account", "123456", "nested-secret", "aabbccdd-1234-5678-9999-aabbccddeeff", "private"] {
        #expect(text.contains(secret) == false)
    }
    let record = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let shape = try #require(record["shape"] as? [String: Any])
    #expect(shape["$type"] as? String == "CubeGame.GetChangesResponse, CubeGame")
    #expect(shape["Code"] as? String == "<number>")
    #expect(shape["Active"] as? String == "<boolean>")
    #expect((shape["Message"] as? [String: String])?["Password"] == "<redacted>")
    #expect((shape["Changes"] as? [[String: String]])?.first?["$type"] == "PlayerEnergyChange")
    let attributes = try FileManager.default.attributesOfItem(atPath: capture.url.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func capturePreservesGameValuesAndAliasesAccountsAcrossMessages() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let capture = try NetworkMessageCapture(directory: directory, expiresAt: Date().addingTimeInterval(60), ownerID: getuid())
    capture.record(Data(#"{"$type":"CubeGame.GameRevealCardChange, SecondDinner.CubeGame","EntityId":51,"StartedInDeckEntityId":-1,"CardDefId":"Rock","AccountId":"private-account","UnknownNumber":987654,"Credentials":{"EntityId":777,"CardDefId":"private-secret"}}"#.utf8),
                   direction: "server-to-client", connection: "test")
    capture.record(Data(#"{"$type":"CubeGame.ChangeNotification, SecondDinner.CubeGame","AccountId":"private-account","Nested":{"SenderAccountId":"private-account","Other":{"AccountId":"other-account"}},"CurrentEnergy":0,"IsWinner":false,"TargetEntityIds":[13,14]}"#.utf8),
                   direction: "server-to-client", connection: "test")
    capture.finish()
    let data = try Data(contentsOf: capture.url)
    let records = try data.split(separator: 0x0a).map { try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]) }
    #expect(records.count == 2)
    let first = try #require(records.first?["shape"] as? [String: Any])
    let second = try #require(records.last?["shape"] as? [String: Any])
    #expect(first["EntityId"] as? Int == 51)
    #expect(first["StartedInDeckEntityId"] as? Int == -1)
    #expect(first["CardDefId"] as? String == "Rock")
    #expect(first["UnknownNumber"] as? String == "<number>")
    #expect(first["Credentials"] as? String == "<redacted>")
    #expect(first["AccountId"] as? String == second["AccountId"] as? String)
    let nested = try #require(second["Nested"] as? [String: Any])
    #expect(nested["SenderAccountId"] as? String == second["AccountId"] as? String)
    #expect((nested["Other"] as? [String: String])?["AccountId"] != second["AccountId"] as? String)
    #expect(second["CurrentEnergy"] as? Int == 0)
    #expect(second["IsWinner"] as? Bool == false)
    #expect(second["TargetEntityIds"] as? [Int] == [13, 14])
    let text = String(decoding: data, as: UTF8.self)
    for secret in ["private-account", "other-account", "private-secret", "987654", "777"] {
        #expect(text.contains(secret) == false)
    }
    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    #expect((directoryAttributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid())
}

@Test func captureRefusesAnExistingDirectoryWithoutOverwritingIt() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let existing = directory.appendingPathComponent("messages.jsonl")
    try Data("keep".utf8).write(to: existing)
    #expect(throws: (any Error).self) {
        _ = try NetworkMessageCapture(directory: directory, expiresAt: Date().addingTimeInterval(60), ownerID: getuid())
    }
    #expect(try String(contentsOf: existing, encoding: .utf8) == "keep")
}

@Test func capturePreservesOwnershipMorphAndRatingFieldsWithoutCredentials() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let capture = try NetworkMessageCapture(directory: directory, expiresAt: Date().addingTimeInterval(60), ownerID: getuid())
    capture.record(Data(#"{"$type":"CubeGame.GetChangesResponse, SecondDinner.CubeGame","Players":[{"InfiniteLeaderboardSkillRating":1234.5,"InfiniteLeaderboardStanding":42,"AccountId":"private-id"}],"Changes":[{"$type":"CubeGame.CardOwnerChange, SecondDinner.CubeGame","EntityId":30,"OwnerEntityId":7,"LocationEntityId":13,"CardZonePosition":0},{"$type":"CubeGame.CardMorphChange, SecondDinner.CubeGame","EntityId":30,"CardDefId":"Hulk","CreatedByPlayerEntityId":7,"OverrideAbilityFromPlayerEntityId":2}],"Credentials":{"InfiniteLeaderboardSkillRating":9999}}"#.utf8),
                   direction: "server-to-client", connection: "test")
    capture.finish()
    let data = try Data(contentsOf: capture.url)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let shape = try #require(root["shape"] as? [String: Any])
    let player = try #require((shape["Players"] as? [[String: Any]])?.first)
    #expect(player["InfiniteLeaderboardSkillRating"] as? Double == 1234.5)
    #expect(player["InfiniteLeaderboardStanding"] as? Int == 42)
    let changes = try #require(shape["Changes"] as? [[String: Any]])
    #expect(changes[0]["OwnerEntityId"] as? Int == 7)
    #expect(changes[0]["CardZonePosition"] as? Int == 0)
    #expect(changes[1]["CardDefId"] as? String == "Hulk")
    #expect(changes[1]["CreatedByPlayerEntityId"] as? Int == 7)
    #expect(changes[1]["OverrideAbilityFromPlayerEntityId"] as? Int == 2)
    #expect(shape["Credentials"] as? String == "<redacted>")
    #expect(String(decoding: data, as: UTF8.self).contains("private-id") == false)
}

@Test func capturePreservesTypedEffectEvidenceWithoutUnmaskingGenericFields() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let capture = try NetworkMessageCapture(directory: directory, expiresAt: Date().addingTimeInterval(60), ownerID: getuid())
    capture.record(Data(#"{"$type":"CubeGame.VfxChange, SecondDinner.CubeGame","$id":"12","Type":"DrawCard","EntityId":"29","Context":[{"$type":"CubeGame.VfxChangeItem, SecondDinner.CubeGame","Key":"CardDefId","Value":{"$type":"CubeGame.VfxString, SecondDinner.CubeGame","String":"Hulk"}},{"$type":"CubeGame.VfxListStrings, SecondDinner.CubeGame","Strings":["Morph","Venus"]},{"$type":"CubeGame.VfxNumber, SecondDinner.CubeGame","Number":-3},{"$type":"CubeGame.CardStatUpdate, SecondDinner.CubeGame","CardDefIdUpdator":"Selene","Value":-3},{"$ref":"12"}],"Other":{"String":"generic-secret","Type":"generic-type","Key":"generic-key","Number":12345,"Value":67890,"Strings":["generic-list-secret"],"$ref":"private-reference"},"Credentials":{"$type":"CubeGame.VfxString, SecondDinner.CubeGame","String":"credential-secret"}}"#.utf8), direction: "server-to-client", connection: "test")
    capture.finish()
    let data = try Data(contentsOf: capture.url)
    let record = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(record["captureFormat"] as? Int == 3)
    let shape = try #require(record["shape"] as? [String: Any])
    #expect(shape["Type"] as? String == "DrawCard")
    #expect(shape["EntityId"] as? String == "29")
    #expect(shape["$id"] as? String == "12")
    let context = try #require(shape["Context"] as? [[String: Any]])
    #expect(context[0]["Key"] as? String == "CardDefId")
    #expect((context[0]["Value"] as? [String: Any])?["String"] as? String == "Hulk")
    #expect(context[1]["Strings"] as? [String] == ["Morph", "Venus"])
    #expect(context[2]["Number"] as? Int == -3)
    #expect(context[3]["CardDefIdUpdator"] as? String == "Selene")
    #expect(context[3]["Value"] as? Int == -3)
    #expect(context[4]["$ref"] as? String == "12")
    let other = try #require(shape["Other"] as? [String: Any])
    #expect(other["String"] as? String == "<string>")
    #expect(other["Number"] as? String == "<number>")
    #expect(other["Value"] as? String == "<number>")
    let text = String(decoding: data, as: UTF8.self)
    for secret in ["generic-secret", "generic-type", "generic-key", "generic-list-secret", "12345", "67890", "private-reference", "credential-secret"] {
        #expect(!text.contains(secret))
    }
}

@Test func captureIgnoresExpiredAndNonJSONMessages() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let capture = try NetworkMessageCapture(directory: directory, expiresAt: .distantPast, ownerID: getuid())
    capture.record(Data(#"{"Token":"secret"}"#.utf8), direction: "client-to-server", connection: "test")
    capture.finish()
    #expect(try Data(contentsOf: capture.url).isEmpty)

    let other = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: other) }
    let active = try NetworkMessageCapture(directory: other, expiresAt: Date().addingTimeInterval(60), ownerID: getuid())
    active.record(Data("not JSON: secret".utf8), direction: "client-to-server", connection: "test")
    active.finish()
    #expect(try Data(contentsOf: active.url).isEmpty)
}

@Test func decodesMaskedClientFramesAcrossChunks() {
    let parser = WebSocketFrameParser()
    var messages: [Data] = []
    parser.onMessage = { messages.append($0) }
    let payload = Data(#"{"$type":"EndTurnRequest"}"#.utf8)
    let mask: [UInt8] = [1, 2, 3, 4]
    var frame = Data([0x81, 0x80 | UInt8(payload.count)] + mask)
    frame.append(contentsOf: payload.enumerated().map { $0.element ^ mask[$0.offset % 4] })
    parser.feed(Data("GET / HTTP/1.1\r\nUpgrade: websocket\r\n\r\n".utf8) + frame.prefix(5))
    #expect(messages.isEmpty)
    parser.feed(frame.dropFirst(5))
    #expect(messages == [payload])
}

@Test func decodesServerFragmentsWithInterleavedPing() {
    let parser = WebSocketFrameParser()
    var messages: [Data] = []
    parser.onMessage = { messages.append($0) }
    parser.feed(Data("HTTP/1.1 101 Switching Protocols\r\n\r\n".utf8)
        + Data([0x01, 2]) + Data("ab".utf8) + Data([0x89, 1, 0x78, 0x80, 2]) + Data("cd".utf8))
    #expect(messages == [Data("abcd".utf8)])
}
