import Foundation
import AVFoundation
import AudioToolbox

/// Wire format: raw AAC-LC, 48 kHz stereo. All methods are called on one audio queue.
final class ReceiverAACDecoder {
    private let converter: AVAudioConverter
    let format: AVAudioFormat

    init?() {
        var description = AudioStreamBasicDescription(
            mSampleRate: 48000, mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: 1024, mBytesPerFrame: 0, mChannelsPerFrame: 2,
            mBitsPerChannel: 0, mReserved: 0)
        guard let input = AVAudioFormat(streamDescription: &description),
              let output = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2),
              let converter = AVAudioConverter(from: input, to: output) else { return nil }
        self.converter = converter
        self.format = output
    }

    func decode(_ data: Data) -> AVAudioPCMBuffer? {
        guard !data.isEmpty, data.count <= 65536 else { return nil }
        let packet = AVAudioCompressedBuffer(format: converter.inputFormat,
            packetCapacity: 1, maximumPacketSize: data.count)
        packet.packetCount = 1
        packet.byteLength = UInt32(data.count)
        data.copyBytes(to: packet.data.assumingMemoryBound(to: UInt8.self), count: data.count)
        packet.packetDescriptions?.pointee = AudioStreamPacketDescription(
            mStartOffset: 0, mVariableFramesInPacket: 1024, mDataByteSize: UInt32(data.count))
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: pcm, error: &error) { _, state in
            guard !supplied else { state.pointee = .noDataNow; return nil }
            supplied = true
            state.pointee = .haveData
            return packet
        }
        guard status != .error, error == nil, pcm.frameLength > 0 else { return nil }
        return pcm
    }
}

/// Catalina-compatible playback through the Mac's selected sound output.
final class ReceiverAudioPlayer {
    private let queue = DispatchQueue(label: "com.bettercast.receiver-audio")
    private var decoder: ReceiverAACDecoder?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var pending = 0
    private var generation = 0
    private var lastPacket = Date.distantPast
    private var failures = 0

    func decode(_ packet: Data) {
        queue.async { [weak self] in self?.play(packet) }
    }

    private func play(_ packet: Data) {
        // Discard queued audio after a pause or route interruption rather than replaying it.
        if Date().timeIntervalSince(lastPacket) > 1 { reset() }
        lastPacket = Date()
        if decoder == nil { decoder = ReceiverAACDecoder() }
        guard let decoder = decoder, let pcm = decoder.decode(packet) else {
            failures += 1
            if failures == 1 || failures % 100 == 0 {
                LogManager.shared.log("Receiver audio: AAC decode failed (packet bytes: \(packet.count))")
            }
            return
        }
        if engine == nil {
            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: decoder.format)
            self.engine = engine
            self.player = node
        }
        guard let engine = engine, let player = player else { return }
        if !engine.isRunning {
            do {
                try engine.start()
                player.play()
                LogManager.shared.log("Receiver audio: Playing AAC, 48000 Hz stereo")
            } catch {
                LogManager.shared.log("Receiver audio: Output start failed: \(error.localizedDescription)")
                reset()
                return
            }
        }
        // Bound latency to roughly 170 ms; completion means played, not just consumed.
        guard pending < 8 else { return }
        pending += 1
        let token = generation
        player.scheduleBuffer(pcm, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self = self else { return }
            self.queue.async {
                guard token == self.generation else { return }
                self.pending = max(0, self.pending - 1)
            }
        }
    }

    func stop() { queue.async { [weak self] in self?.reset() } }

    private func reset() {
        generation += 1
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        decoder = nil
        pending = 0
    }
}
