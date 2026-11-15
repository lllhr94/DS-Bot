// Starts a Relay Server and a computer-side link with the project's own code,
// then writes a pairing code to the file named on the command line.
// The Swift tests pair with it, so both ends are checked against each other.
import { writeFileSync } from 'node:fs'
import { DeviceRegistry, HostLink, deviceIdFor, generateKeyPair, pairingUri, randomToken } from '../../link/src/index.ts'
import { startRelayServer } from '../../link/server/server.ts'

const out = process.argv[2]
if (out === undefined) throw new Error('usage: node harness.mjs <file for the pairing code>')

const server = await startRelayServer({ host: '127.0.0.1' })
const keys = generateKeyPair()
const self = { deviceId: deviceIdFor(keys.publicKey), ...keys }
const registry = new DeviceRegistry()
const host = new HostLink({
  url: server.url,
  identity: self,
  accessToken: randomToken(),
  name: 'Desk',
  admits: (deviceId, key) => registry.admits(deviceId, key),
  authorize: (deviceId, key, hello) => registry.authorize(deviceId, key, hello),
  handle: async (method, params) => {
    if (method === 'emit') { host.emit('tick', params); return { ok: true } }
    if (method === 'fail') throw Object.assign(new Error('The computer said no.'), { code: 'NOPE' })
    return { method, params }
  },
})
host.start()
await host.waitOnline()
const { code } = registry.openPairing(30 * 60_000)
writeFileSync(out, pairingUri({ server: server.url, hostDeviceId: self.deviceId, hostKey: self.publicKey, code, name: 'Desk' }))
console.log(`harness ready at ${server.url}`)
