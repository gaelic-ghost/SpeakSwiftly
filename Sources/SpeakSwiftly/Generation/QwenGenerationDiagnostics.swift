#if DEBUG
import Foundation
@preconcurrency import MLX
import MLXAudioTTS
@preconcurrency import MLXLMCommon

struct QwenGenerationDiagnostics {
    let initialReferenceFingerprint: QwenReferenceFingerprint
    private(set) var primaryCodecTokenDigest = StableDebugDigest()
    private(set) var audioSampleDigest = StableDebugDigest()
    private(set) var primaryCodecTokenCount = 0
    private(set) var audioChunkCount = 0
    private(set) var audioSampleCount = 0

    init(reference: SpeakSwiftly.Runtime.QwenGenerationReference) {
        initialReferenceFingerprint = QwenReferenceFingerprint(reference: reference)
    }

    mutating func record(_ event: ModelGenerationEvent) {
        switch event {
            case let .token(token):
                primaryCodecTokenDigest.combine(token)
                primaryCodecTokenCount += 1
            case .info:
                break
            case let .audio(samples):
                audioSampleDigest.combine(samples)
                audioChunkCount += 1
                audioSampleCount += samples.count
        }
    }

    func startedDetails(
        generationParameters: GenerateParameters,
        text: String,
        chunkIndex: Int?,
    ) -> [String: WorkerLogValue] {
        var details: [String: WorkerLogValue] = [
            "debug_only": .bool(true),
            "reference_kind": .string(initialReferenceFingerprint.kind),
            "reference_fingerprint_before": .string(initialReferenceFingerprint.digest),
            "text_fingerprint": .string(StableDebugDigest.digest(text.utf8)),
            "text_character_count": .int(text.count),
            "temperature": .double(Double(generationParameters.temperature)),
            "top_p": .double(Double(generationParameters.topP)),
            "top_k": .int(generationParameters.topK),
            "repetition_penalty": .double(Double(generationParameters.repetitionPenalty ?? 1)),
            "max_tokens": .int(generationParameters.maxTokens ?? 0),
        ]
        details.merge(initialReferenceFingerprint.componentDetails, uniquingKeysWith: { _, new in new })
        if let chunkIndex {
            details["chunk_index"] = .int(chunkIndex)
        }
        return details
    }

    func finishedDetails(
        reference: SpeakSwiftly.Runtime.QwenGenerationReference,
        outcome: String,
        chunkIndex: Int?,
    ) -> [String: WorkerLogValue] {
        let finalReferenceFingerprint = QwenReferenceFingerprint(reference: reference)
        var details: [String: WorkerLogValue] = [
            "debug_only": .bool(true),
            "outcome": .string(outcome),
            "reference_kind": .string(finalReferenceFingerprint.kind),
            "reference_fingerprint_before": .string(initialReferenceFingerprint.digest),
            "reference_fingerprint_after": .string(finalReferenceFingerprint.digest),
            "reference_unchanged": .bool(initialReferenceFingerprint == finalReferenceFingerprint),
            "primary_codec_token_digest": .string(primaryCodecTokenDigest.hex),
            "primary_codec_token_count": .int(primaryCodecTokenCount),
            "audio_sample_digest": .string(audioSampleDigest.hex),
            "audio_chunk_count": .int(audioChunkCount),
            "audio_sample_count": .int(audioSampleCount),
        ]
        if let chunkIndex {
            details["chunk_index"] = .int(chunkIndex)
        }
        return details
    }
}

struct QwenReferenceFingerprint: Equatable {
    let kind: String
    let digest: String
    let componentDetails: [String: WorkerLogValue]

    init(reference: SpeakSwiftly.Runtime.QwenGenerationReference) {
        switch reference {
            case let .raw(materialization, refAudio):
                kind = "raw_reference_audio"
                let audioDigest = refAudio.map(StableDebugDigest.digestFloats) ?? "none"
                let textDigest = StableDebugDigest.digest(materialization.manifest.referenceText.utf8)
                digest = StableDebugDigest.digest("\(audioDigest):\(textDigest)".utf8)
                componentDetails = [
                    "reference_audio_fingerprint": .string(audioDigest),
                    "reference_audio_shape": .string(refAudio.map { String(describing: $0.shape) } ?? "none"),
                    "reference_text_fingerprint": .string(textDigest),
                ]

            case let .prepared(conditioning):
                kind = "prepared_conditioning"
                let speakerEmbeddingDigest = conditioning.speakerEmbedding
                    .map(StableDebugDigest.digestFloats) ?? "none"
                let speechCodesDigest = StableDebugDigest.digestInt32(conditioning.referenceSpeechCodes)
                let textTokenDigest = StableDebugDigest.digestInt32(conditioning.referenceTextTokenIDs)
                let codecLanguageID = conditioning.codecLanguageID.map(String.init) ?? "none"
                digest = StableDebugDigest.digest(
                    "\(speakerEmbeddingDigest):\(speechCodesDigest):\(textTokenDigest):\(conditioning.resolvedLanguage):\(codecLanguageID)".utf8,
                )
                componentDetails = [
                    "speaker_embedding_fingerprint": .string(speakerEmbeddingDigest),
                    "speaker_embedding_shape": .string(conditioning.speakerEmbedding.map { String(describing: $0.shape) } ?? "none"),
                    "reference_speech_codes_fingerprint": .string(speechCodesDigest),
                    "reference_speech_codes_shape": .string(String(describing: conditioning.referenceSpeechCodes.shape)),
                    "reference_text_tokens_fingerprint": .string(textTokenDigest),
                    "reference_text_tokens_shape": .string(String(describing: conditioning.referenceTextTokenIDs.shape)),
                    "resolved_language": .string(conditioning.resolvedLanguage),
                    "codec_language_id": .string(codecLanguageID),
                ]
        }
    }

    static func == (lhs: QwenReferenceFingerprint, rhs: QwenReferenceFingerprint) -> Bool {
        lhs.kind == rhs.kind && lhs.digest == rhs.digest
    }
}

struct StableDebugDigest {
    private static let offsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01B3

    private var value = offsetBasis

    var hex: String {
        String(format: "%016llx", value)
    }

    static func digest(_ bytes: some Sequence<UInt8>) -> String {
        var digest = StableDebugDigest()
        for byte in bytes {
            digest.combine(byte)
        }
        return digest.hex
    }

    static func digestFloats(_ array: MLXArray) -> String {
        var digest = StableDebugDigest()
        for dimension in array.shape {
            digest.combine(dimension)
        }
        digest.combine(array.asArray(Float.self))
        return digest.hex
    }

    static func digestInt32(_ array: MLXArray) -> String {
        var digest = StableDebugDigest()
        for dimension in array.shape {
            digest.combine(dimension)
        }
        for value in array.asArray(Int32.self) {
            digest.combine(value.littleEndian)
        }
        return digest.hex
    }

    mutating func combine(_ value: Int) {
        combine(Int64(value).littleEndian)
    }

    mutating func combine(_ values: [Float]) {
        for value in values {
            combine(value.bitPattern.littleEndian)
        }
    }

    private mutating func combine(_ value: some FixedWidthInteger) {
        withUnsafeBytes(of: value) { bytes in
            for byte in bytes {
                combine(byte)
            }
        }
    }

    private mutating func combine(_ byte: UInt8) {
        value ^= UInt64(byte)
        value &*= Self.prime
    }
}
#endif
