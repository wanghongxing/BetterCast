#!/usr/bin/env python3
"""Decode real AAC packets and test mute restoration without touching speaker settings."""
import math, struct, subprocess, tempfile, wave
from pathlib import Path
root=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='bc-audio-') as folder:
    folder=Path(folder)
    wav=folder/'tone.wav'; aac=folder/'tone.aac'
    with wave.open(str(wav),'wb') as output:
        output.setnchannels(2); output.setsampwidth(2); output.setframerate(48000)
        output.writeframes(b''.join(struct.pack('<hh', *([int(8000*math.sin(2*math.pi*440*i/48000))]*2)) for i in range(24000)))
    subprocess.run(['afconvert','-f','adts','-d','aac','-b','128000',str(wav),str(aac)],check=True)
    source=r'''
import Foundation
import CoreAudio
class LogManager { static let shared = LogManager(); func log(_ text: String) { print(text) } }
let data = [UInt8](try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let decoder = ReceiverAACDecoder()!
var offset = 0
var frames = 0
var peak: Float = 0
while offset + 7 <= data.count {
    precondition(data[offset] == 0xff)
    let length = (Int(data[offset+3] & 3) << 11) | (Int(data[offset+4]) << 3) | Int(data[offset+5] >> 5)
    let header = (data[offset+1] & 1) == 1 ? 7 : 9
    precondition(length > header && offset + length <= data.count)
    let packet = Data(data[(offset+header)..<(offset+length)])
    if let pcm = decoder.decode(packet) {
        frames += Int(pcm.frameLength)
        for i in 0..<Int(pcm.frameLength) { peak = max(peak, abs(pcm.floatChannelData![0][i])) }
    }
    offset += length
}
precondition(frames > 18000 && peak > 0.05, "AAC did not decode audible PCM")
print("PASS: AAC 48kHz stereo decoded: \(frames) frames, peak \(peak)")
precondition(decoder.decode(Data()) == nil)

final class FakeOutput: SenderSoundOutput {
    var device: AudioDeviceID = 1
    var muted: [AudioDeviceID: Bool] = [1:false, 2:true]
    var writable = true
    func defaultDevice() -> AudioDeviceID? { device }
    func muteState(_ id: AudioDeviceID) -> Bool? { muted[id] }
    func setMuted(_ value: Bool, device: AudioDeviceID) -> Bool {
        guard writable else { return false }; muted[device] = value; return true
    }
}
let output = FakeOutput()
let mute = SenderAudioMute(output:output)
precondition(mute.update(active:true) == nil && output.muted[1] == true)
_ = mute.update(active:false)
precondition(output.muted[1] == false)
_ = mute.update(active:true)
output.device = 2
_ = mute.update(active:true)
precondition(output.muted[1] == false && output.muted[2] == true)
mute.restore()
precondition(output.muted[2] == true)
output.device = 1; output.writable = false
precondition(mute.update(active:true) != nil && output.muted[1] == false)
print("PASS: mute enable/disable, device change, prior mute preservation, unsupported device")
'''
    (folder/'main.swift').write_text(source)
    subprocess.run(['swiftc','-target','x86_64-apple-macosx10.15',
        str(root/'Sources/BetterCastSender/ReceiverAudioPlayer.swift'),
        str(root/'Sources/BetterCastSender/SenderAudioMute.swift'),str(folder/'main.swift'),'-o',str(folder/'test')],check=True)
    subprocess.run([str(folder/'test'),str(aac)],check=True)
