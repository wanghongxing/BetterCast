#!/usr/bin/env python3
"""Exercise the production roaming methods with real local Bonjour/TCP sockets.
Capture/display dependencies are fakes; no screen permission or real stream is needed.
Requires two advertised interfaces (normally Wi-Fi and Thunderbolt Bridge).
"""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[2]
source = (root/'Sources/BetterCastSender/BetterCastSenderApp.swift').read_text()
start = source.index('    // Keep capture, encoder and virtual display alive')
end = source.index('    /// Switch an already-connected Android device', start)
methods = source[start:end]
preamble = r'''
import Foundation
import Network
class LogManager { static let shared = LogManager(); func log(_ message: String) { print(message) } }
class Capture { func stopCapture() {} }
class Display { var destroyed = false; func destroyDisplay() { destroyed = true } }
class Encoder { func forceKeyframe() {} }
class InputHandler { static let shared = InputHandler(); func removeDisplayBounds(for id: UUID) {} }
struct DiscoveredService { var name: String; var endpoint: NWEndpoint; var networkInterfaces: [NWInterface] }
struct ConnectionPipeline {
    var connection: NWConnection
    var service: DiscoveredService
    var lastHeartbeat = Date()
    var isLoopback = false
    var isP2P = false
    var pendingSends = 0
    var sendInProgress = false
    var screenRecorder: Capture? = Capture()
    var virtualDisplayManager: Display? = Display()
    var videoEncoder: Encoder? = Encoder()
}
enum Preference { case auto, wiredCable, p2pOnly, preferEthernet, preferWiFi, routerOnly, preferThunderbolt }
class NetworkClient {
    var connectionType = "TCP"
    var interfacePreference = Preference.preferThunderbolt
    var manuallyDisconnectedNames = Set<String>()
    var dismissedServiceNames = Set<String>()
    var pipelines: [UUID: ConnectionPipeline] = [:]
    var foundServices: [DiscoveredService] = []
    var connectedServices: [DiscoveredService] = []
    var connectedDisplays: [String] = []
    var status = ""
    var heartbeatTimer: Timer?
    func updateConnectedDisplays() {}
    func synchronizeSenderMute() {}
    func receive(on connection: NWConnection, connectionId: UUID) {}
'''
checks = r'''
    func run(_ service: DiscoveredService) {
        let candidates = service.networkInterfaces.filter { $0.type != .loopback }.sorted { routeRank($0) < routeRank($1) }
        guard let preferred = candidates.first,
              let lower = candidates.last, routeRank(preferred) < routeRank(lower) else {
            fputs("SKIP: need two advertised interfaces of different priority\n", stderr); exit(77)
        }
        guard case .service(let name, let type, let domain, _) = service.endpoint else { fatalError() }
        func connection(on interface: NWInterface) -> NWConnection {
            let p = NWParameters.tcp; p.requiredInterface = interface
            return NWConnection(to: .service(name:name,type:type,domain:domain,interface:interface),using:p)
        }
        print("Routes", candidates.map { "\($0.name):\(routeRank($0))" })
        if let wifi = candidates.first(where: { $0.type == .wifi && !$0.name.hasPrefix("awdl") }) {
            interfacePreference = .preferWiFi
            precondition(routeRank(wifi) == 0)
            interfacePreference = .wiredCable
            precondition(routeRank(wifi) == 100, "Cable-only must not use Wi-Fi")
        }
        if let ethernet = candidates.first(where: { $0.type == .wiredEthernet && !ConnectionNetwork.thunderboltNames().contains($0.name) }) {
            interfacePreference = .preferEthernet
            precondition(routeRank(ethernet) == 0)
        }
        interfacePreference = .preferThunderbolt
        print("PASS: preferred network ranking and cable-only restrictions")
        let old = connection(on:lower)
        old.stateUpdateHandler = { print("Initial route:", $0) }
        old.start(queue:.main)
        wait { if case .ready = old.state { return true }; return false }
        let id = UUID()
        pipelines[id] = ConnectionPipeline(connection:old,service:service)
        let display = pipelines[id]!.virtualDisplayManager!
        foundServices = [service]; connectedServices = [service]
        reconcileNetworkRoutes()
        precondition(routeAttempts.isEmpty, "Must debounce upgrades")
        // A stale Bonjour record must not tear down the working route.
        foundServices[0].endpoint = .service(name:"missing-" + UUID().uuidString,type:type,domain:domain,interface:nil)
        stableRoutes[id] = (preferred.name, Date().addingTimeInterval(-5))
        reconcileNetworkRoutes()
        wait { self.routeAttempts.isEmpty }
        precondition(pipelines[id]?.connection === old && !display.destroyed)
        precondition(failedRoutes[id]?[preferred.name] != nil)
        print("PASS: failed upgrade retains old connection and quarantines failed route")
        foundServices = [service]
        failedRoutes[id] = [:]; routeRetryAfter[id] = .distantPast
        stableRoutes[id] = (preferred.name, Date().addingTimeInterval(-5))
        reconcileNetworkRoutes()
        wait { self.pipelines[id]?.connection !== old && self.routeAttempts.isEmpty }
        precondition(pipelines[id]?.virtualDisplayManager === display && !display.destroyed)
        print("PASS: preferred-route upgrade preserves virtual display and pipeline ID")

        let upgraded = pipelines[id]!.connection
        removeConnection(id)
        precondition(recoveringRoutes.contains(id))
        wait { self.pipelines[id]?.connection !== upgraded && !self.recoveringRoutes.contains(id) }
        precondition(pipelines[id]?.virtualDisplayManager === display && !display.destroyed)
        print("PASS: unexpected disconnect falls back without destroying display")

        routeRetryAfter[id] = .distantPast
        failedRoutes[id] = [:]
        stableRoutes[id] = (preferred.name, Date().addingTimeInterval(-5))
        reconcileNetworkRoutes()
        let pending = routeAttempts[id]
        disconnectConnection(id)
        precondition(pipelines[id] == nil && routeAttempts.isEmpty && recoveringRoutes.isEmpty)
        precondition(display.destroyed && manuallyDisconnectedNames.contains(service.name))
        if let pending = pending { precondition(pending.stateUpdateHandler == nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        reconcileNetworkRoutes()
        precondition(pipelines.isEmpty)
        print("PASS: manual disconnect cancels pending migration and suppresses recovery")
    }
}
func wait(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(10)
    while !condition() && Date() < deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.05)) }
    precondition(condition(), "Timed out")
}
setbuf(stdout, nil)
let listener = try NWListener(using: .tcp)
let name = "BetterCast-route-test-" + UUID().uuidString
listener.service = NWListener.Service(name:name,type:"_bcroutetest._tcp")
var accepted: [NWConnection] = []
listener.newConnectionHandler = { connection in accepted.append(connection); connection.start(queue:.main) }
listener.start(queue:.main)
let browser = NWBrowser(for:.bonjour(type:"_bcroutetest._tcp",domain:nil),using:.tcp)
var discovered: DiscoveredService?
browser.browseResultsChangedHandler = { results, _ in
    if let result = results.first(where: { if case .service(let n,_,_,_) = $0.endpoint { return n == name }; return false }) {
        discovered = DiscoveredService(name:name,endpoint:result.endpoint,networkInterfaces:result.interfaces)
    }
}
browser.start(queue:.main)
wait { discovered != nil }
print("Discovered", discovered!.networkInterfaces)
// Allow additional interface announcements to merge before selecting routes.
RunLoop.main.run(until:Date().addingTimeInterval(1))
NetworkClient().run(discovered!)
browser.cancel(); listener.cancel(); accepted.forEach { $0.cancel() }
'''
with tempfile.TemporaryDirectory(prefix='bc-roaming-') as directory:
    path = Path(directory)
    (path/'main.swift').write_text(preamble + methods + checks)
    subprocess.run(['swiftc',str(root/'Sources/BetterCastSender/ConnectionNetwork.swift'),str(path/'main.swift'),'-o',str(path/'test')],check=True)
    subprocess.run([str(path/'test')],check=True)
