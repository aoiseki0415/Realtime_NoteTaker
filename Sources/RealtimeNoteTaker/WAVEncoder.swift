import AVFoundation
import Foundation

enum WAVEncoder {
    static func encode(buffer: AVAudioPCMBuffer) throws -> Data {
        let format = buffer.format
        guard format.commonFormat == .pcmFormatFloat32,
              let channels = buffer.floatChannelData else {
            throw WAVEncoderError.unsupportedFormat
        }

        let channelCount = Int(format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var samples = Data(capacity: frameCount * channelCount * MemoryLayout<Int16>.size)
        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                let sample = max(-1.0, min(1.0, channels[channel][frame]))
                var value = Int16(sample * Float(Int16.max)).littleEndian
                samples.append(Data(bytes: &value, count: MemoryLayout<Int16>.size))
            }
        }

        return wavData(samples: samples, sampleRate: Int(format.sampleRate), channelCount: channelCount)
    }

    static func wavData(samples: Data, sampleRate: Int, channelCount: Int) -> Data {
        let bitsPerSample = 16
        let blockAlign = channelCount * bitsPerSample / 8
        let byteRate = sampleRate * blockAlign
        let fileSize = 36 + samples.count
        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        appendUInt32(UInt32(fileSize), to: &wav)
        wav.append("WAVEfmt ".data(using: .ascii)!)
        appendUInt32(16, to: &wav)
        appendUInt16(1, to: &wav)
        appendUInt16(UInt16(channelCount), to: &wav)
        appendUInt32(UInt32(sampleRate), to: &wav)
        appendUInt32(UInt32(byteRate), to: &wav)
        appendUInt16(UInt16(blockAlign), to: &wav)
        appendUInt16(UInt16(bitsPerSample), to: &wav)
        wav.append("data".data(using: .ascii)!)
        appendUInt32(UInt32(samples.count), to: &wav)
        wav.append(samples)
        return wav
    }

    static func pcm16Data(from buffer: AVAudioPCMBuffer) throws -> Data {
        let format = buffer.format
        guard format.commonFormat == .pcmFormatFloat32,
              let channels = buffer.floatChannelData else {
            throw WAVEncoderError.unsupportedFormat
        }
        let channelCount = Int(format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var samples = Data(capacity: frameCount * channelCount * MemoryLayout<Int16>.size)
        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                let sample = max(-1.0, min(1.0, channels[channel][frame]))
                var value = Int16(sample * Float(Int16.max)).littleEndian
                samples.append(Data(bytes: &value, count: MemoryLayout<Int16>.size))
            }
        }
        return samples
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        data.append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        data.append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }
}

final class AudioChunkAccumulator {
    private let sampleRate: Int
    private let channelCount: Int
    private let targetFrameCount: Int
    private var frames = 0
    private var samples = Data()

    init(format: AVAudioFormat, duration: TimeInterval = 4) {
        self.sampleRate = Int(format.sampleRate)
        self.channelCount = Int(format.channelCount)
        self.targetFrameCount = max(1, Int(format.sampleRate * duration))
    }

    func append(_ buffer: AVAudioPCMBuffer) throws -> Data? {
        guard Int(buffer.format.sampleRate) == sampleRate,
              Int(buffer.format.channelCount) == channelCount else {
            throw WAVEncoderError.unsupportedFormat
        }
        samples.append(try WAVEncoder.pcm16Data(from: buffer))
        frames += Int(buffer.frameLength)
        guard frames >= targetFrameCount else { return nil }
        let wav = WAVEncoder.wavData(samples: samples, sampleRate: sampleRate, channelCount: channelCount)
        frames = 0
        samples.removeAll(keepingCapacity: true)
        return wav
    }
}

enum WAVEncoderError: LocalizedError {
    case unsupportedFormat
    var errorDescription: String? { "未対応の音声形式です。" }
}
