import AppKit
import Combine

/// Track the video area so the pointer is usable in the title bar and on other screens.
final class ReceiverContainerView: NSView {
    var onPointerPresenceChange: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onPointerPresenceChange?(true) }
    override func mouseExited(with event: NSEvent) { onPointerPresenceChange?(false) }
}

// AppKit lifecycle (not SwiftUI @main App, which is macOS 11+) so this runs back to 10.15.
// Receiver-only: wire the shared core and drop the renderer's NSView straight into a window.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let listener = ReceiverNetworkListener()
    private let decoder = ReceiverVideoDecoder()
    private let renderer = ReceiverVideoRenderer()
    private let statusLabel = NSTextField(labelWithString: "Waiting for a Mac to connect…")
    private var localCursorHidden = false
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
        let container = ReceiverContainerView(frame: frame)
        container.onPointerPresenceChange = { [weak self] inside in
            if inside { self?.synchronizeLocalCursor() } else { self?.setLocalCursorHidden(false) }
        }
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

        listener.$connectionNetwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] network in
                self?.window.title = "BetterCast Receiver — " + network
            }
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

    private func setLocalCursorHidden(_ hidden: Bool) {
        guard hidden != localCursorHidden else { return }
        localCursorHidden = hidden
        if hidden { NSCursor.hide() } else { NSCursor.unhide() }
    }

    private func synchronizeLocalCursor() {
        guard let window = window, let content = window.contentView else {
            setLocalCursorHidden(false)
            return
        }
        let point = content.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        setLocalCursorHidden(window.styleMask.contains(.fullScreen) && NSApp.isActive &&
            window.isKeyWindow && content.bounds.contains(point))
    }

    func windowDidResize(_ notification: Notification) {
        synchronizeVideoLayout()
        synchronizeLocalCursor()
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        synchronizeVideoLayout()
        synchronizeLocalCursor()
    }
    func windowWillExitFullScreen(_ notification: Notification) { setLocalCursorHidden(false) }
    func windowDidExitFullScreen(_ notification: Notification) {
        synchronizeVideoLayout()
        setLocalCursorHidden(false)
    }
    func windowDidBecomeKey(_ notification: Notification) { synchronizeLocalCursor() }
    func windowDidResignKey(_ notification: Notification) { setLocalCursorHidden(false) }
    func windowWillClose(_ notification: Notification) { setLocalCursorHidden(false) }
    func applicationDidBecomeActive(_ notification: Notification) { synchronizeLocalCursor() }
    func applicationDidResignActive(_ notification: Notification) { setLocalCursorHidden(false) }
    func applicationWillTerminate(_ notification: Notification) { setLocalCursorHidden(false) }
    func windowDidChangeBackingProperties(_ notification: Notification) { synchronizeVideoLayout() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
