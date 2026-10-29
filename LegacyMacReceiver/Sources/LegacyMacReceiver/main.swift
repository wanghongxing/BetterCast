import AppKit
import Combine

// AppKit lifecycle (not SwiftUI @main App, which is macOS 11+) so this runs back to 10.15.
// Receiver-only: wire the shared core and drop the renderer's NSView straight into a window.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let listener = ReceiverNetworkListener()
    private let decoder = ReceiverVideoDecoder()
    private let renderer = ReceiverVideoRenderer()
    private let statusLabel = NSTextField(labelWithString: "Waiting for a Mac to connect…")
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.delegate = self
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.title = "BetterCast Receiver"
        window.center()

        // Container hosts the video NSView (fills) + a centered status label on top.
        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        let video = renderer.view
        video.frame = container.bounds
        video.autoresizingMask = [.width, .height]
        container.addSubview(video)

        statusLabel.textColor = .white
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Show the listener status while waiting, and hide the overlay once a sender connects
        // (connectedClients is populated on accept — a reliable signal, unlike videoSize).
        listener.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.statusLabel.stringValue = status ?? "" }
            .store(in: &cancellables)
        listener.$connectedClients
            .receive(on: DispatchQueue.main)
            .sink { [weak self] clients in self?.statusLabel.isHidden = !clients.isEmpty }
            .store(in: &cancellables)

        listener.setup(decoder: decoder, renderer: renderer)
        listener.start()
    }

    private func synchronizeVideoLayout() {
        guard let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        renderer.view.frame = content.bounds
        renderer.layout()
    }

    func windowDidResize(_ notification: Notification) { synchronizeVideoLayout() }
    func windowDidEnterFullScreen(_ notification: Notification) { synchronizeVideoLayout() }
    func windowDidExitFullScreen(_ notification: Notification) { synchronizeVideoLayout() }
    func windowDidChangeBackingProperties(_ notification: Notification) { synchronizeVideoLayout() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
