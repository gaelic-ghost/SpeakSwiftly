@preconcurrency import AVFoundation
import Foundation
import SpeakSwiftlyCore

public enum NetworkAudioPayloadFormat: String, Codable, Sendable, Equatable, CaseIterable {
    case aac
}

public struct NetworkGeneratedAudioFrame: Codable, Sendable, Equatable {
    public let requestID: String
    public let sequenceNumber: Int
    public let sampleRate: Int
    public let channelCount: Int
    public let sourceSampleFormat: GeneratedAudioSampleFormat
    public let payloadFormat: NetworkAudioPayloadFormat
    public let payloadStreamDescription: NetworkAudioStreamDescription
    public let isFinal: Bool
    public let packetCount: Int
    public let maximumPacketSize: Int
    public let packetDescriptions: [NetworkAudioPacketDescription]
    public let payload: Data

    public init(
        requestID: String,
        sequenceNumber: Int,
        sampleRate: Int,
        channelCount: Int,
        sourceSampleFormat: GeneratedAudioSampleFormat,
        payloadFormat: NetworkAudioPayloadFormat,
        payloadStreamDescription: NetworkAudioStreamDescription,
        isFinal: Bool,
        packetCount: Int,
        maximumPacketSize: Int,
        packetDescriptions: [NetworkAudioPacketDescription],
        payload: Data,
    ) {
        self.requestID = requestID
        self.sequenceNumber = sequenceNumber
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.sourceSampleFormat = sourceSampleFormat
        self.payloadFormat = payloadFormat
        self.payloadStreamDescription = payloadStreamDescription
        self.isFinal = isFinal
        self.packetCount = packetCount
        self.maximumPacketSize = maximumPacketSize
        self.packetDescriptions = packetDescriptions
        self.payload = payload
    }
}

public struct NetworkAudioStreamDescription: Codable, Sendable, Equatable {
    public let sampleRate: Double
    public let formatID: UInt32
    public let formatFlags: UInt32
    public let bytesPerPacket: UInt32
    public let framesPerPacket: UInt32
    public let bytesPerFrame: UInt32
    public let channelsPerFrame: UInt32
    public let bitsPerChannel: UInt32

    var audioStreamBasicDescription: AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: formatID,
            mFormatFlags: formatFlags,
            mBytesPerPacket: bytesPerPacket,
            mFramesPerPacket: framesPerPacket,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channelsPerFrame,
            mBitsPerChannel: bitsPerChannel,
            mReserved: 0,
        )
    }

    public init(
        sampleRate: Double,
        formatID: UInt32,
        formatFlags: UInt32,
        bytesPerPacket: UInt32,
        framesPerPacket: UInt32,
        bytesPerFrame: UInt32,
        channelsPerFrame: UInt32,
        bitsPerChannel: UInt32,
    ) {
        self.sampleRate = sampleRate
        self.formatID = formatID
        self.formatFlags = formatFlags
        self.bytesPerPacket = bytesPerPacket
        self.framesPerPacket = framesPerPacket
        self.bytesPerFrame = bytesPerFrame
        self.channelsPerFrame = channelsPerFrame
        self.bitsPerChannel = bitsPerChannel
    }

    init(_ streamDescription: AudioStreamBasicDescription) {
        self.init(
            sampleRate: streamDescription.mSampleRate,
            formatID: streamDescription.mFormatID,
            formatFlags: streamDescription.mFormatFlags,
            bytesPerPacket: streamDescription.mBytesPerPacket,
            framesPerPacket: streamDescription.mFramesPerPacket,
            bytesPerFrame: streamDescription.mBytesPerFrame,
            channelsPerFrame: streamDescription.mChannelsPerFrame,
            bitsPerChannel: streamDescription.mBitsPerChannel,
        )
    }
}

public struct NetworkAudioPacketDescription: Codable, Sendable, Equatable {
    public let startOffset: Int64
    public let variableFramesInPacket: UInt32
    public let dataByteSize: UInt32

    public init(
        startOffset: Int64,
        variableFramesInPacket: UInt32,
        dataByteSize: UInt32,
    ) {
        self.startOffset = startOffset
        self.variableFramesInPacket = variableFramesInPacket
        self.dataByteSize = dataByteSize
    }

    init(_ packetDescription: AudioStreamPacketDescription) {
        self.init(
            startOffset: packetDescription.mStartOffset,
            variableFramesInPacket: packetDescription.mVariableFramesInPacket,
            dataByteSize: packetDescription.mDataByteSize,
        )
    }

    var audioStreamPacketDescription: AudioStreamPacketDescription {
        AudioStreamPacketDescription(
            mStartOffset: startOffset,
            mVariableFramesInPacket: variableFramesInPacket,
            mDataByteSize: dataByteSize,
        )
    }
}

public struct NetworkAudioStreamHandshake: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let requestID: String
    public let senderName: String
    public let sharedToken: String

    public init(
        protocolVersion: Int = NetworkAudioBonjour.protocolVersion,
        requestID: String,
        senderName: String,
        sharedToken: String,
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.senderName = senderName
        self.sharedToken = sharedToken
    }
}

public enum NetworkAudioStreamFrame: Sendable, Equatable {
    case handshake(NetworkAudioStreamHandshake)
    case audio(NetworkGeneratedAudioFrame)
}

extension NetworkGeneratedAudioFrame {
    struct Header: Codable {
        let requestID: String
        let sequenceNumber: Int
        let sampleRate: Int
        let channelCount: Int
        let sourceSampleFormat: GeneratedAudioSampleFormat
        let payloadFormat: NetworkAudioPayloadFormat
        let payloadStreamDescription: NetworkAudioStreamDescription
        let isFinal: Bool
        let packetCount: Int
        let maximumPacketSize: Int
        let packetDescriptions: [NetworkAudioPacketDescription]
        let payloadByteCount: Int
    }

    var header: Header {
        Header(
            requestID: requestID,
            sequenceNumber: sequenceNumber,
            sampleRate: sampleRate,
            channelCount: channelCount,
            sourceSampleFormat: sourceSampleFormat,
            payloadFormat: payloadFormat,
            payloadStreamDescription: payloadStreamDescription,
            isFinal: isFinal,
            packetCount: packetCount,
            maximumPacketSize: maximumPacketSize,
            packetDescriptions: packetDescriptions,
            payloadByteCount: payload.count,
        )
    }

    init(header: Header, payload: Data) {
        self.init(
            requestID: header.requestID,
            sequenceNumber: header.sequenceNumber,
            sampleRate: header.sampleRate,
            channelCount: header.channelCount,
            sourceSampleFormat: header.sourceSampleFormat,
            payloadFormat: header.payloadFormat,
            payloadStreamDescription: header.payloadStreamDescription,
            isFinal: header.isFinal,
            packetCount: header.packetCount,
            maximumPacketSize: header.maximumPacketSize,
            packetDescriptions: header.packetDescriptions,
            payload: payload,
        )
    }
}
