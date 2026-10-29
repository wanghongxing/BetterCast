import Foundation
import CoreAudio

protocol SenderSoundOutput {
    func defaultDevice() -> AudioDeviceID?
    func muteState(_ device: AudioDeviceID) -> Bool?
    func setMuted(_ muted: Bool, device: AudioDeviceID) -> Bool
}

struct SystemSoundOutput: SenderSoundOutput {
    func defaultDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMaster)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }
    func muteState(_ device: AudioDeviceID) -> Bool? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMaster)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }
    func setMuted(_ muted: Bool, device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMaster)
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}

/// Main-thread only. Restore the user's prior state, including an already-muted device.
final class SenderAudioMute {
    static let shared = SenderAudioMute(output: SystemSoundOutput())
    private let output: SenderSoundOutput
    private var saved: (device: AudioDeviceID, muted: Bool)?
    init(output: SenderSoundOutput) { self.output = output }

    func update(active: Bool) -> String? {
        guard active else { restore(); return nil }
        guard let device = output.defaultDevice() else { restore(); return "No sound output device" }
        if saved?.device == device { return nil }
        restore()
        guard let previous = output.muteState(device), output.setMuted(true, device: device) else {
            return "This sound output does not support software mute"
        }
        saved = (device, previous)
        return nil
    }

    func restore() {
        guard let previous = saved else { return }
        // If the user already unmuted it, leave their newer choice alone.
        if output.muteState(previous.device) == true {
            _ = output.setMuted(previous.muted, device: previous.device)
        }
        saved = nil
    }
}
