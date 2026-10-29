import Foundation
import AppKit
import Network
let app = NSApplication.shared
let listener = ReceiverNetworkListener(tcpPort: 0)
let renderer = ReceiverVideoRenderer()
listener.setup(decoder: ReceiverVideoDecoder(), renderer: renderer)
listener.start()
func waitUntil(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(8)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    if !condition() { fputs("Timed out: \(listener.status ?? "nil") clients=\(listener.connectedClients.count)\n", stderr); exit(1) }
}
waitUntil { listener.tcpListener?.port != nil }
let client = NWConnection(host: "127.0.0.1", port: listener.tcpListener!.port!, using: .tcp)
client.start(queue: .global())
waitUntil { !listener.connectedClients.isEmpty }
client.cancel()
waitUntil { listener.connectedClients.isEmpty && listener.status?.contains("disconnected") == true }
precondition(renderer.videoSize == .zero)
listener.stop()
print("PASS: connection path display, TCP disconnect cleanup, stop")
