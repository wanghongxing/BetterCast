# Implementation notes

Moved from our additions to the upstream README. Paths are relative to the repository root.

### Local network-priority build (Catalina receiver)

Run `contributions/scripts/build_local_network_apps.sh` to create certificate-signed apps in
`local-build/`. The sender runs on the main Mac; the receiver is compiled for
Intel macOS 10.15 explicitly (newer SwiftPM/Xcode versions may silently raise its
deployment target). These builds are not notarized and automatic upstream update
checks are disabled. Do not run the original receiver and this receiver together.

In the sender, disconnect first, then open Connection → Mode and choose
**Prefer Thunderbolt Bridge**, **Prefer Ethernet**, or **Prefer Wi-Fi**. Reconnect
using the Bonjour-discovered iMac entry. The preference is saved. The first dial
is bound to the selected interface advertised by that receiver; on failure or a
five-second timeout it retries using normal routing. If the selected interface
was not discovered, normal connection selection applies immediately. Auto also
prefers a discovered Thunderbolt interface. Manual IP entries keep their explicit
address/routing and do not carry Bonjour interface preferences. Existing Cable
mode still forbids Wi-Fi fallback. TCP Bonjour sessions automatically migrate to a stable higher-priority route.

The legacy receiver displays the connection path's interfaces and remote address
in the window title, which updates on network changes. Fullscreen video has no
network-text overlay. The local cursor is hidden over the active fullscreen video
and restored in windowed mode, over the title bar, on focus loss or normal exit. Thunderbolt identification uses the system
hardware interface description, not an assumed bridge0 or a renamed service.
TCP EOF/errors clear the retained image; TCP keepalive probes detect silent peers
(idle 5 seconds, interval 2 seconds, 3 probes; actual timing is OS-controlled).
After 15 seconds without decoded video the image is also hidden with a paused
status, without declaring a static/UDP stream disconnected; new frames recover it.

Run `contributions/scripts/test_receiver_connection.sh` for an isolated loopback connection and
disconnect smoke test. Real Thunderbolt selection/fallback and Catalina runtime
behavior still require testing on the two physical Macs.

The Catalina receiver synchronizes video geometry on resize, fullscreen entry/exit,
and backing-scale changes. Video resizing uses content-local coordinates and
suppresses Core Animation position/size animations. The smoke test also checks
1280×720 → 1920×1080 → 1280×720 geometry; actual Catalina fullscreen transitions
must still be verified on the iMac.


### Automatic network recovery

For TCP connections to Bonjour-discovered receivers, the sender retains the
virtual display and capture pipeline during an unexpected disconnect and probes
other advertised interfaces. The receiver does not need an update for this change.
The preferred interface must remain visible for 4 seconds before an upgrade; the
old socket stays active until the new TCP connection is ready. Each probe has a
6-second deadline, failed routes wait 20 seconds before another attempt, and
successful migrations have a 10-second upgrade cooldown. Actual connection loss
bypasses that cooldown. All unavailable routes are retried while the session is
wanted; manually Disconnecting or deleting the receiver cancels recovery.

Auto/Prefer Thunderbolt rank Thunderbolt, Ethernet, Wi-Fi, then AWDL. Prefer
Ethernet and Prefer Wi-Fi put the selected type first. Cable-only and P2P-only
retain their restrictions. This recovery currently applies to TCP Bonjour
sessions, not manual IP, UDP, or ADB/USB tunnels. Device matching uses the existing
Bonjour service name; a renamed receiver must be selected again. Recovery starts
only after an initial successful connection and does not persist across quitting
the sender. During outages the virtual display remains present until manually
disconnected, so windows do not move to the MacBook screen.

`contributions/scripts/test_network_roaming.py` runs the production recovery methods against real
local Bonjour/TCP sockets with fake capture/display resources. It checks failed
upgrades, successful upgrades, fallback, preservation of the display object, and
manual cancellation. It needs two advertised network interfaces; it does not
replace unplug/replug testing with the physical iMac.


Local builds now require a real Apple Development or Developer ID Application
signing identity. The first build selects the sole matching identity and pins its
fingerprint in ignored `local-build/.signing-identity`; later builds fail instead
of silently reverting to ad-hoc signing if that identity is unavailable. Override
with `SIGN_IDENTITY` when intentionally changing certificates. No private key or
certificate is stored in this repository. Switching from the earlier ad-hoc build
requires granting Screen Recording and Accessibility again for the installed app.


### Catalina receiver audio and sender mute

The Mac receiver now decodes type-0x02 raw AAC-LC packets and plays them through
its selected system sound output using AVAudioEngine. The sender requests 48 kHz
stereo capture explicitly to match the wire format. The per-device Audio Streaming
switch now gates transmitted audio and attaches/detaches the encoder live. Normal
ScreenCaptureKit sessions remain audio-capture-capable while the switch is off,
but no audio is encoded or transmitted. Compatibility Mode has no audio.

Mute Sender is a separate, initially-off switch in Settings and the connected
receiver controls. While an audio-enabled stream is connected, it mutes the Mac's
default output device, including other local app sound. Disabling it, disconnecting,
or normally quitting restores the previous mute state; output changes restore the
old device before muting the new one. Devices without software mute show a message
instead. Force-killing the app cannot run restoration; use the system mute control
if needed. This switch is not persisted across app launches.

Run `python3 contributions/scripts/test_receiver_audio.py` to decode a generated AAC test tone
and test mute-state restoration with fake output devices, without playing sound or
changing real sound settings. Both the updated sender and receiver are required;
actual iMac speaker playback and muted-sender capture need an end-to-end check.
