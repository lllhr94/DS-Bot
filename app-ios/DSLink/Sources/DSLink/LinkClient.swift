import Foundation

/// What this phone tells the computer inside the encrypted handshake.
public struct LinkHello: Sendable {
    public var name: String?
    public var pairingCode: String?

    public init(name: String? = nil, pairingCode: String? = nil) {
        self.name = name
        self.pairingCode = pairingCode
    }
}

/// Something the computer pushed to the phone. `data` is JSON.
public struct LinkEvent: Sendable {
    public let name: String
    public let data: Data
}

/// One encrypted connection from this phone to its paired computer, through the Relay Server.
/// A client connects once: after it closes, make a new one.
public actor LinkClient {
    /// Events from the computer. The stream ends when the connection closes.
    public nonisolated let events: AsyncStream<LinkEvent>
    private let eventSink: AsyncStream<LinkEvent>.Continuation

    private let identity: LinkIdentity
    private let host: PairedHost
    private let hello: LinkHello

    private var socket: URLSessionWebSocketTask?
    private var noise: NoiseIKInitiator?
    private var connectionId = ""
    private var counter = 0
    private var incoming = SecureMessageCodec()
    private var outgoing = SecureMessageCodec()
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var reader: Task<Void, Never>?
    private var ended = false

    /// Why the connection ended, once it has.
    public private(set) var closeReason: LinkError?
    /// The name the computer gave itself in the handshake.
    public private(set) var hostName: String?

    public init(identity: LinkIdentity, host: PairedHost, hello: LinkHello = LinkHello()) {
        self.identity = identity
        self.host = host
        self.hello = hello
        let (stream, sink) = AsyncStream.makeStream(of: LinkEvent.self)
        events = stream
        eventSink = sink
    }

    public var connected: Bool { noise != nil && !ended }

    public func connect(timeout: TimeInterval = 10) async throws {
        guard socket == nil, !ended else { throw LinkError("ALREADY_USED", "This connection was already used.") }
        guard let url = URL(string: host.server) else { throw LinkError("SERVER_UNREACHABLE", "The Server address is invalid.") }
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 4 * 1024 * 1024
        socket = task
        task.resume()
        // Ending the socket is what stops a handshake that hangs.
        let deadline = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if !Task.isCancelled { task.cancel(with: .goingAway, reason: nil) }
        }
        defer { deadline.cancel() }
        do {
            try await handshake(task)
        } catch {
            let reason = (error as? LinkError) ?? LinkError("SERVER_UNREACHABLE", "The computer could not be reached: \(error.localizedDescription)")
            finish(reason)
            throw reason
        }
        reader = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let raw = try await task.receive()
                    guard let self else { return }
                    await self.handle(raw)
                } catch {
                    await self?.finish(LinkError("TRANSPORT_CLOSED", "The link closed: \(error.localizedDescription)"))
                    return
                }
            }
        }
    }

    /// Calls the computer once. `params` and the result are JSON.
    public func call(_ method: String, params: Data = Data("{}".utf8), timeout: TimeInterval = 30) async throws -> Data {
        guard connected else { throw closeReason ?? LinkError("NOT_CONNECTED", "The phone is not connected to the computer.") }
        let id = Wire.newId()
        let body = try Wire.message(
            "rpc.request",
            ["method": method, "params": try JSONSerialization.jsonObject(with: params, options: [.fragmentsAllowed])],
            id: id
        )
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try sendSecure(body)
            } catch {
                pending[id] = nil
                continuation.resume(throwing: error)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self?.fail(id, LinkError("RPC_TIMEOUT", "The computer did not answer \(method) in time."))
            }
        }
    }

    public func close() {
        finish(LinkError("CLIENT_CLOSED", "The phone closed the connection."))
    }

    // MARK: Setting up

    private func handshake(_ task: URLSessionWebSocketTask) async throws {
        send(task, try Wire.control("hello", [
            "role": "client",
            "deviceId": identity.deviceId,
            "identityKey": identity.publicKey,
            "accessToken": identity.accessToken,
            "protocols": [Wire.version],
            "capabilities": [Wire.relayCapability],
        ]))
        let ack = try await nextFrame(task, "hello.ack")
        guard (ack["protocol"] as? Int) == Wire.version else {
            throw LinkError("UNSUPPORTED_SERVER", "The Server uses a version this app does not support.")
        }
        guard let capabilities = ack["capabilities"] as? [String], capabilities.contains(Wire.relayCapability) else {
            throw LinkError("UNSUPPORTED_SERVER", "The Server cannot relay messages.")
        }

        send(task, try Wire.control("connect.request", ["hostDeviceId": host.deviceId]))
        let accepted = try await nextFrame(task, "connect.accepted")
        guard let id = accepted["connectionId"] as? String, !id.isEmpty else {
            throw LinkError("BAD_FRAME", "The Server did not name the connection.")
        }
        connectionId = id

        guard let privateKey = Base64URL.decode(identity.privateKey), let hostKey = Base64URL.decode(host.identityKey) else {
            throw LinkError("INVALID_KEY", "A stored key is damaged.")
        }
        // Binds the handshake to this one connection between these two devices.
        let prologue = Data("DS-BOT-LINK\0v=1\0connection=\(id)\0host=\(host.deviceId)\0client=\(identity.deviceId)".utf8)
        let session = try NoiseIKInitiator(localPrivateKey: privateKey, remotePublicKey: hostKey, prologue: prologue)
        var greeting: [String: Any] = [:]
        if let name = hello.name { greeting["name"] = String(name.prefix(64)) }
        if let code = hello.pairingCode { greeting["pairingCode"] = code }
        let first = try session.writeFirstMessage(payload: try JSONSerialization.data(withJSONObject: greeting))
        send(task, try Wire.control("secure.handshake", [
            "connectionId": id,
            "targetDeviceId": host.deviceId,
            "step": 1,
            "data": Base64URL.encode(first),
        ]))

        let reply = try await nextFrame(task, "secure.handshake")
        guard (reply["connectionId"] as? String) == id,
              (reply["targetDeviceId"] as? String) == identity.deviceId,
              (reply["step"] as? Int) == 2,
              let data = (reply["data"] as? String).flatMap(Base64URL.decode) else {
            throw LinkError("HANDSHAKE_FAILED", "The secure handshake arrived out of order.")
        }
        let answer: Data
        do {
            answer = try session.readSecondMessage(data)
        } catch {
            throw LinkError("PEER_IDENTITY_MISMATCH", "The computer's key does not match the paired key.")
        }
        if !answer.isEmpty, let said = try? JSONSerialization.jsonObject(with: answer) as? [String: Any] {
            hostName = said["name"] as? String
        }
        noise = session
    }

    /// Reads until the wanted frame arrives; answers pings and stops on a refusal.
    private func nextFrame(_ task: URLSessionWebSocketTask, _ wanted: String) async throws -> [String: Any] {
        while true {
            guard case .string(let text) = try await task.receive() else {
                throw LinkError("BAD_FRAME", "The Server sent a frame that is not text.")
            }
            let frame = try Wire.parse(Data(text.utf8))
            if frame.type == wanted { return frame.payload }
            if frame.type == "ping" { send(task, try Wire.control("pong", frame.payload)) }
            if frame.type == "error" || frame.type == "connect.rejected" { throw Self.refusal(frame.payload) }
        }
    }

    private static func refusal(_ payload: [String: Any]) -> LinkError {
        LinkError(
            payload["code"] as? String ?? "REJECTED",
            payload["message"] as? String ?? "The computer refused the connection."
        )
    }

    // MARK: Running

    private func handle(_ raw: URLSessionWebSocketTask.Message) {
        guard !ended, let task = socket else { return }
        do {
            guard case .string(let text) = raw else { throw LinkError("BAD_FRAME", "The Server sent a frame that is not text.") }
            let frame = try Wire.parse(Data(text.utf8))
            switch frame.type {
            case "relay":
                guard (frame.payload["connectionId"] as? String) == connectionId,
                      (frame.payload["targetDeviceId"] as? String) == identity.deviceId,
                      let sealed = (frame.payload["ciphertext"] as? String).flatMap(Base64URL.decode),
                      let noise else {
                    throw LinkError("BAD_FRAME", "A message arrived for an unknown connection.")
                }
                if let message = try incoming.decode(try noise.decrypt(sealed)) { try deliver(message) }
            case "ping":
                send(task, try Wire.control("pong", frame.payload))
            case "error", "connect.rejected":
                finish(Self.refusal(frame.payload))
            default:
                break
            }
        } catch {
            finish((error as? LinkError) ?? LinkError("DECRYPT_FAILED", "A message from the computer could not be read."))
        }
    }

    private func deliver(_ message: Data) throws {
        let (type, payload) = try Wire.parse(message)
        switch type {
        case "rpc.response":
            guard let id = payload["requestId"] as? String, let waiting = pending.removeValue(forKey: id) else { return }
            waiting.resume(returning: Wire.json(payload["result"]))
        case "rpc.error":
            guard let id = payload["requestId"] as? String else { return }
            fail(id, LinkError(payload["code"] as? String ?? "RPC_ERROR", payload["message"] as? String ?? "The computer reported an error."))
        case "event":
            guard let name = payload["event"] as? String else { return }
            eventSink.yield(LinkEvent(name: name, data: Wire.json(payload["data"])))
        default:
            break
        }
    }

    /// Encrypts and sends in one step, with no suspension between: Noise counters must reach the computer in order.
    private func sendSecure(_ message: Data) throws {
        guard let noise, let task = socket, !ended else { throw LinkError("NOT_CONNECTED", "The phone is not connected to the computer.") }
        for piece in try outgoing.encode(message) {
            send(task, try Wire.control("relay", [
                "connectionId": connectionId,
                "targetDeviceId": host.deviceId,
                "counter": counter,
                "ciphertext": Base64URL.encode(try noise.encrypt(piece)),
            ]))
            counter += 1
        }
    }

    private func send(_ task: URLSessionWebSocketTask, _ text: String) {
        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { await self?.finish(LinkError("TRANSPORT_CLOSED", "The link closed: \(error.localizedDescription)")) }
        }
    }

    private func fail(_ id: String, _ error: LinkError) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func finish(_ reason: LinkError) {
        guard !ended else { return }
        ended = true
        closeReason = reason
        noise = nil
        reader?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        let waiting = pending
        pending = [:]
        for (_, continuation) in waiting { continuation.resume(throwing: reason) }
        eventSink.finish()
    }
}

public extension LinkClient {
    /// The same call with Swift values on both sides.
    func call<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        _ method: String,
        _ params: Params,
        returning: Result.Type = Result.self,
        timeout: TimeInterval = 30
    ) async throws -> Result {
        let data = try await call(method, params: try JSONEncoder().encode(params), timeout: timeout)
        return try JSONDecoder().decode(Result.self, from: data)
    }
}
