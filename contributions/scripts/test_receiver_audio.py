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

'''
    (folder/'main.swift').write_text(source)
    subprocess.run(['swiftc','-target','x86_64-apple-macosx10.15',
        str(root/'Sources/BetterCastSender/ReceiverAudioPlayer.swift'),
        str(folder/'main.swift'),'-o',str(folder/'test')],check=True)
    subprocess.run([str(folder/'test'),str(aac)],check=True)
