import DSLink
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Screen { case welcome, pair, home }

    @Published private(set) var screen: Screen
    @Published private(set) var host: PairedHost?
    let team = TeamModel()
    private let identity: LinkIdentity

    init() {
        if let saved = Vault.load(LinkIdentity.self, key: "identity") {
            identity = saved
        } else {
            let fresh = LinkIdentity.generate()
            Vault.save(fresh, as: "identity")
            identity = fresh
        }
        let saved = Vault.load(PairedHost.self, key: "host")
        host = saved
        screen = saved == nil ? .welcome : .home
        if let saved { team.start(identity: identity, host: saved) }
    }

    func go(_ next: Screen) {
        withAnimation(.smooth(duration: 0.5)) { screen = next }
    }

    /// Pairs with the computer the code names. The code goes only inside the encrypted handshake.
    func pair(_ offer: PairingOffer) async throws {
        let client = LinkClient(identity: identity, host: offer.host, hello: LinkHello(name: "iPhone", pairingCode: offer.code))
        try await client.connect()
        let name = await client.hostName
        await client.close()
        var paired = offer.host
        if let name, !name.isEmpty { paired.name = name }
        Vault.save(paired, as: "host")
        host = paired
        team.start(identity: identity, host: paired)
        go(.home)
    }

    func startDemo() {
        team.showDemo()
        go(.home)
    }

    func leave() {
        team.stop()
        Vault.remove("host")
        host = nil
        go(.welcome)
    }
}
