import AVFoundation
import Foundation
import Observation
import Supabase

private final class PCMSink: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func take() -> Data {
        lock.lock()
        defer { data = Data(); lock.unlock() }
        return data
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return data.count
    }
}

@MainActor
@Observable
final class VoiceMeter {
    var recording = false
    var transcribing = false
    var samples = Array(repeating: CGFloat(0.18), count: 14)
    var error: String?
    private let engine = AVAudioEngine()
    private var tapped = false
    private let sink = PCMSink()
    nonisolated private static let rate = 16_000.0
    nonisolated private static let limit = Int(rate) * 2 * 55

    func begin() {
        Task { await start() }
    }

    private func start() async {
        error = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Allow the microphone in Settings to talk."
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            return
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.rate, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: format, to: target) else { return }
        _ = sink.take()
        if tapped { input.removeTap(onBus: 0) }
        let block = Self.tap(sink: sink, converter: converter, target: target, source: format) { [weak self] level in
            Task { @MainActor in self?.push(level) }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: block)
        tapped = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapped = false
            return
        }
        recording = true
    }

    nonisolated private static func tap(
        sink: PCMSink,
        converter: AVAudioConverter,
        target: AVAudioFormat,
        source: AVAudioFormat,
        level: @escaping @Sendable (CGFloat) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            if let channel = buffer.floatChannelData?[0] {
                var sum: Float = 0
                for index in 0..<count { sum += channel[index] * channel[index] }
                level(CGFloat(sqrt(sum / Float(count))) * 12)
            }
            let capacity = AVAudioFrameCount(Double(count) * rate / source.sampleRate) + 64
            guard sink.count < limit,
                  let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var fed = false
            converter.convert(to: out, error: nil) { _, status in
                if fed {
                    status.pointee = .noDataNow
                    return nil
                }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            guard let pcm = out.int16ChannelData?[0], out.frameLength > 0 else { return }
            sink.append(Data(bytes: pcm, count: Int(out.frameLength) * 2))
        }
    }

    private func push(_ level: CGFloat) {
        samples.removeFirst()
        samples.append(min(1, max(0.18, level)))
    }

    func stop() {
        guard tapped || engine.isRunning || recording else { return }
        if tapped { engine.inputNode.removeTap(onBus: 0) }
        tapped = false
        if engine.isRunning { engine.stop() }
        recording = false
        samples = Array(repeating: 0.18, count: 14)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func finish() async -> String? {
        stop()
        let pcm = sink.take()
        guard pcm.count > Int(Self.rate) / 2 else { return nil }
        transcribing = true
        defer { transcribing = false }
        do {
            let reply: Transcript = try await TernedBackend.client.functions.invoke(
                "transcribe",
                options: FunctionInvokeOptions(body: Clip(audio: Self.wav(pcm).base64EncodedString(), format: "wav"))
            )
            let text = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            self.error = "Couldn't hear that. Try again."
            return nil
        }
    }

    private struct Clip: Encodable {
        var audio: String
        var format: String
    }

    private struct Transcript: Decodable {
        var text: String
    }

    private static func wav(_ pcm: Data) -> Data {
        var data = Data()
        func put(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func put(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        put(UInt32(36 + pcm.count))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        put(UInt32(16))
        put(UInt16(1))
        put(UInt16(1))
        put(UInt32(rate))
        put(UInt32(rate * 2))
        put(UInt16(2))
        put(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        put(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}
