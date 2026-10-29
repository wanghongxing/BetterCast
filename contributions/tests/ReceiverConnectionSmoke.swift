import Foundation
import AppKit
import Network
let app = NSApplication.shared
let listener = ReceiverNetworkListener(tcpPort: 0)
let renderer = ReceiverVideoRenderer()
// Simulate a centered window expanding to 1080p fullscreen and returning.
let host = NSView(frame: NSRect(x: 320, y: 200, width: 1280, height: 720))
renderer.view.frame = host.bounds
renderer.view.autoresizingMask = [.width, .height]
host.addSubview(renderer.view)
for size in [NSSize(width: 1920, height: 1080), NSSize(width: 1280, height: 720)] {
    host.setFrameSize(size)
    host.layoutSubtreeIfNeeded()
    precondition(renderer.view.frame == host.bounds)
    guard let videoLayer = renderer.view.layer?.sublayers?.first else { fatalError("No video layer") }
    precondition(videoLayer.frame == renderer.view.bounds, "Video shifted after resize")
    precondition(videoLayer.animationKeys()?.isEmpty != false)
}
print("PASS: window/fullscreen-size geometry and no layer animation")
listener.setup(decoder: ReceiverVideoDecoder(), renderer: renderer)
listener.start()
func waitUntil(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(8)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    if !condition() { fputs("Timed out: \(listener.status ?? "nil") clients=\(listener.connectedClients.count) network=\(listener.connectionNetwork)\n", stderr); exit(1) }
}
waitUntil { listener.tcpListener?.port != nil }
let client = NWConnection(host: "127.0.0.1", port: listener.tcpListener!.port!, using: .tcp)
client.start(queue: .global())
waitUntil { !listener.connectedClients.isEmpty }
fputs("Network: \(listener.connectionNetwork)\n", stderr)
precondition(listener.connectionNetwork.contains("Loopback"), listener.connectionNetwork)
client.cancel()
waitUntil { listener.connectedClients.isEmpty && listener.status?.contains("disconnected") == true }
precondition(listener.connectionNetwork == "Not connected")
precondition(renderer.videoSize == .zero)
listener.stop()
print("PASS: connection path display, TCP disconnect cleanup, stop")
