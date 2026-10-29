import Foundation
import Network
import SystemConfiguration

/// Use the system hardware description, not a user-renamed service or an assumed bridge0.
enum ConnectionNetwork {
    static func thunderboltNames() -> Set<String> {
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        return Set(interfaces.compactMap { interface in
            guard let name = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let label = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?,
                  label.localizedCaseInsensitiveContains("Thunderbolt") || label.contains("雷雳") || label.contains("雷電") else { return nil }
            return name
        })
    }

    static func description(for connection: NWConnection) -> String {
        guard let path = connection.currentPath else { return "Network: determining…" }
        let thunderbolt = thunderboltNames()
        let labels = path.availableInterfaces.map { interface -> String in
            let kind: String
            if thunderbolt.contains(interface.name) { kind = "Thunderbolt Bridge" }
            else if interface.type == .wifi { kind = "Wi-Fi" }
            else if interface.type == .wiredEthernet { kind = "Ethernet" }
            else if interface.type == .loopback { kind = "Loopback" }
            else { kind = "Network" }
            return "\(kind) (\(interface.name))"
        }
        let peer = path.remoteEndpoint.map { String(describing: $0) } ?? String(describing: connection.endpoint)
        return "\(labels.joined(separator: " + ")) → \(peer)"
    }
}
