import XCTest
@testable import DSLink

final class CodecTests: XCTestCase {
    func testShortMessagePassesThrough() throws {
        var codec = SecureMessageCodec()
        let message = Data("hello".utf8)
        XCTAssertEqual(try codec.encode(message), [message])
        XCTAssertEqual(try codec.decode(message), message)
    }

    func testLongMessageSplitsAndJoins() throws {
        var sender = SecureMessageCodec()
        var receiver = SecureMessageCodec()
        let message = Data((0..<200_000).map { UInt8($0 % 251) })
        let frames = try sender.encode(message)
        XCTAssertEqual(frames.count, 5)
        var joined: Data?
        for frame in frames {
            XCTAssertNil(joined)
            joined = try receiver.decode(frame)
        }
        XCTAssertEqual(joined, message)
        var stranger = SecureMessageCodec()
        XCTAssertThrowsError(try stranger.decode(frames[1]))
    }

    func testBase64URL() {
        let bytes = Data((0..<256).map { UInt8($0) })
        let text = Base64URL.encode(bytes)
        XCTAssertNil(text.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
        XCTAssertEqual(Base64URL.decode(text), bytes)
    }

    func testPairingCode() throws {
        let me = LinkIdentity.generate()
        XCTAssertEqual(try LinkKeys.deviceId(forPublicKey: me.publicKey), me.deviceId)
        XCTAssertEqual(LinkKeys.fingerprint(ofPublicKey: me.publicKey).count, 12)
        let uri = "dsbot://pair?v=1&server=wss%3A%2F%2Flink.example%2Fv1%2Flink&host=\(me.deviceId)&key=\(me.publicKey)&code=abc&name=My+Desk"
        let offer = try PairingOffer.parse(uri)
        XCTAssertEqual(offer.server, "wss://link.example/v1/link")
        XCTAssertEqual(offer.name, "My Desk")
        XCTAssertEqual(offer.code, "abc")
        let other = LinkIdentity.generate()
        XCTAssertThrowsError(try PairingOffer.parse(uri.replacingOccurrences(of: me.publicKey, with: other.publicKey)))
        XCTAssertThrowsError(try PairingOffer.parse("https://example.com"))
    }
}

/// Talks to the real computer-side code. The workflow starts it and passes the pairing code in.
final class InteropTests: XCTestCase {
    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testPairCallEventAndComeBack() async throws {
        guard let uri = ProcessInfo.processInfo.environment["DSLINK_PAIRING_URI"], !uri.isEmpty else {
            throw XCTSkip("No computer to talk to: DSLINK_PAIRING_URI is not set.")
        }
        let offer = try PairingOffer.parse(uri)
        let me = LinkIdentity.generate()

        // 1. Pair with the code.
        let first = LinkClient(identity: me, host: offer.host, hello: LinkHello(name: "iPhone", pairingCode: offer.code))
        try await first.connect()
        let hostName = await first.hostName
        XCTAssertEqual(hostName, "Desk")

        // 2. A call goes there and back.
        let small = try object(try await first.call("bot.call", params: Data(#"{"endpoint":"state"}"#.utf8)))
        XCTAssertEqual(small["method"] as? String, "bot.call")
        XCTAssertEqual((small["params"] as? [String: Any])?["endpoint"] as? String, "state")

        // 3. So does one long enough to be split into pieces, both ways.
        let long = String(repeating: "z", count: 300_000)
        let echoed = try object(try await first.call("bot.call", params: try JSONSerialization.data(withJSONObject: ["big": long])))
        XCTAssertEqual((echoed["params"] as? [String: Any])?["big"] as? String, long)

        // 4. Several calls at once keep their order on the wire.
        try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<20 {
                group.addTask {
                    let reply = try await first.call("bot.call", params: Data(#"{"n":\#(index)}"#.utf8))
                    let params = (try JSONSerialization.jsonObject(with: reply) as? [String: Any])?["params"] as? [String: Any]
                    return params?["n"] as? Int ?? -1
                }
            }
            var seen = Set<Int>()
            for try await value in group { seen.insert(value) }
            XCTAssertEqual(seen, Set(0..<20))
        }

        // 5. The computer can push an event.
        _ = try await first.call("emit", params: Data(#"{"n":7}"#.utf8))
        let event = await withTaskGroup(of: LinkEvent?.self) { group in
            group.addTask {
                for await event in first.events { return event }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return nil
            }
            let winner = await group.next() ?? nil
            group.cancelAll()
            return winner
        }
        XCTAssertEqual(event?.name, "tick")
        XCTAssertEqual(try object(try XCTUnwrap(event?.data))["n"] as? Int, 7)

        // 6. An error from the computer comes back as an error.
        do {
            _ = try await first.call("fail")
            XCTFail("The call should have failed.")
        } catch let error as LinkError {
            XCTAssertEqual(error.code, "NOPE")
        }

        await first.close()
        let after = await first.connected
        XCTAssertFalse(after)

        // 7. The paired phone comes back without the code.
        let second = LinkClient(identity: me, host: offer.host)
        try await second.connect()
        let again = try object(try await second.call("bot.call", params: Data(#"{"endpoint":"again"}"#.utf8)))
        XCTAssertEqual((again["params"] as? [String: Any])?["endpoint"] as? String, "again")
        await second.close()

        // 8. A phone that never paired is refused.
        let stranger = LinkClient(identity: LinkIdentity.generate(), host: offer.host)
        do {
            try await stranger.connect(timeout: 5)
            XCTFail("An unpaired phone connected.")
        } catch {
            // Expected.
        }

        // 9. A phone that expects a different computer key does not get through.
        let wrongHost = PairedHost(deviceId: offer.hostDeviceId, identityKey: LinkIdentity.generate().publicKey, server: offer.server, name: "")
        let fooled = LinkClient(identity: me, host: wrongHost)
        do {
            try await fooled.connect(timeout: 5)
            XCTFail("A computer with the wrong key was accepted.")
        } catch {
            // Expected.
        }
    }
}
