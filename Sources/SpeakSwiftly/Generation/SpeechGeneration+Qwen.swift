import Foundation
@preconcurrency import MLX
import MLXAudioTTS
@preconcurrency import MLXLMCommon

// MARK: - Qwen Speech Generation

extension SpeakSwiftly.Runtime {
    func generationEventInfo(from info: ModelGenerationEvent.Info) -> SpeakSwiftly.GenerationEventInfo {
        SpeakSwiftly.GenerationEventInfo(
            promptTokenCount: info.promptTokenCount,
            generationTokenCount: info.generationTokenCount,
            prefillTime: info.prefillTime,
            generateTime: info.generateTime,
            tokensPerSecond: info.tokensPerSecond,
            peakMemoryUsage: info.peakMemoryUsage,
        )
    }

    func qwenGenerationStream(
        requestID: String,
        model: AnySpeechModel,
        text: String,
        materialization: StoredProfileMaterialization,
        refAudio: MLXArray?,
        generationParameters: GenerateParameters,
        streamingInterval: Double,
    ) -> AsyncThrowingStream<[Float], Error> {
        let plannedChunks = {
            let chunks = LiveSpeechChunkPlanner.chunks(
                for: text,
                strategy: .smartParagraphGroups(),
            )
            return chunks.isEmpty ? [
                LiveSpeechTextChunk(
                    index: 1,
                    text: text,
                    wordCount: 1,
                    segmentation: .sentenceGroup,
                ),
            ] : chunks
        }()

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for plannedChunk in plannedChunks {
                        try Task.checkCancellation()

                        let eventStream = model.generateEventStream(
                            text: plannedChunk.text,
                            voice: nil,
                            refAudio: refAudio,
                            refText: materialization.manifest.referenceText,
                            language: nil,
                            generationParameters: generationParameters,
                            streamingInterval: streamingInterval,
                        )

                        for try await event in eventStream {
                            switch event {
                                case let .token(token):
                                    recordGenerationEvent(.token(token), for: requestID)
                                case let .info(info):
                                    recordGenerationEvent(.info(generationEventInfo(from: info)), for: requestID)
                                case let .audio(samples):
                                    recordGenerationEvent(.audioChunk(sampleCount: samples.count), for: requestID)
                                    continuation.yield(samples)
                            }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func qwenLiveGenerationStream(
        requestID: String,
        op: String?,
        profileName: String,
        model: AnySpeechModel,
        text: String,
        plannedChunks: [LiveSpeechTextChunk]?,
        materialization: StoredProfileMaterialization,
        refAudio: MLXArray?,
        generationParameters: GenerateParameters,
        streamingInterval: Double,
    ) -> AsyncThrowingStream<[Float], Error> {
        let plannedChunks = plannedChunks ?? {
            let chunks = LiveSpeechChunkPlanner.chunks(
                for: text,
                strategy: .smartParagraphGroups(),
            )
            return chunks.isEmpty ? [
                LiveSpeechTextChunk(
                    index: 1,
                    text: text,
                    wordCount: 1,
                    segmentation: .sentenceGroup,
                ),
            ] : chunks
        }()

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for plannedChunk in plannedChunks {
                        try Task.checkCancellation()

                        let startedAt = Date()
                        var sawFirstAudio = false
                        var audioChunkCount = 0
                        var sampleCount = 0

                        await logQwenLiveChunkStarted(
                            requestID: requestID,
                            op: op,
                            profileName: profileName,
                            chunk: plannedChunk,
                            totalChunkCount: plannedChunks.count,
                            streamingInterval: streamingInterval,
                        )

                        let eventStream = model.generateEventStream(
                            text: plannedChunk.text,
                            voice: nil,
                            refAudio: refAudio,
                            refText: materialization.manifest.referenceText,
                            language: nil,
                            generationParameters: generationParameters,
                            streamingInterval: streamingInterval,
                        )

                        for try await event in eventStream {
                            switch event {
                                case let .token(token):
                                    recordGenerationEvent(.token(token), for: requestID)
                                case let .info(info):
                                    recordGenerationEvent(.info(generationEventInfo(from: info)), for: requestID)
                                case let .audio(samples):
                                    audioChunkCount += 1
                                    sampleCount += samples.count
                                    recordGenerationEvent(.audioChunk(sampleCount: samples.count), for: requestID)
                                    if !sawFirstAudio {
                                        sawFirstAudio = true
                                        await logQwenLiveChunkFirstAudio(
                                            requestID: requestID,
                                            op: op,
                                            profileName: profileName,
                                            chunk: plannedChunk,
                                            totalChunkCount: plannedChunks.count,
                                            timeToFirstAudioMS: Int((Date().timeIntervalSince(startedAt) * 1000).rounded()),
                                            sampleCount: samples.count,
                                        )
                                    }
                                    continuation.yield(samples)
                            }
                        }

                        await logQwenLiveChunkFinished(
                            requestID: requestID,
                            op: op,
                            profileName: profileName,
                            chunk: plannedChunk,
                            totalChunkCount: plannedChunks.count,
                            elapsedMS: Int((Date().timeIntervalSince(startedAt) * 1000).rounded()),
                            audioChunkCount: audioChunkCount,
                            sampleCount: sampleCount,
                        )
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func qwenGenerationStream(
        requestID: String,
        model: AnySpeechModel,
        text: String,
        conditioning: Qwen3TTSModel.Qwen3TTSReferenceConditioning,
        generationParameters: GenerateParameters,
        streamingInterval: Double,
    ) -> AsyncThrowingStream<[Float], Error> {
        let plannedChunks = {
            let chunks = LiveSpeechChunkPlanner.chunks(
                for: text,
                strategy: .smartParagraphGroups(),
            )
            return chunks.isEmpty ? [
                LiveSpeechTextChunk(
                    index: 1,
                    text: text,
                    wordCount: 1,
                    segmentation: .sentenceGroup,
                ),
            ] : chunks
        }()

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for plannedChunk in plannedChunks {
                        try Task.checkCancellation()

                        let eventStream = model.generateConditionedEventStream(
                            text: plannedChunk.text,
                            conditioning: conditioning,
                            generationParameters: generationParameters,
                            streamingInterval: streamingInterval,
                        )

                        for try await event in eventStream {
                            switch event {
                                case let .token(token):
                                    recordGenerationEvent(.token(token), for: requestID)
                                case let .info(info):
                                    recordGenerationEvent(.info(generationEventInfo(from: info)), for: requestID)
                                case let .audio(samples):
                                    recordGenerationEvent(.audioChunk(sampleCount: samples.count), for: requestID)
                                    continuation.yield(samples)
                            }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func qwenLiveGenerationStream(
        requestID: String,
        op: String?,
        profileName: String,
        model: AnySpeechModel,
        text: String,
        plannedChunks: [LiveSpeechTextChunk]?,
        conditioning: Qwen3TTSModel.Qwen3TTSReferenceConditioning,
        generationParameters: GenerateParameters,
        streamingInterval: Double,
    ) -> AsyncThrowingStream<[Float], Error> {
        let plannedChunks = plannedChunks ?? {
            let chunks = LiveSpeechChunkPlanner.chunks(
                for: text,
                strategy: .smartParagraphGroups(),
            )
            return chunks.isEmpty ? [
                LiveSpeechTextChunk(
                    index: 1,
                    text: text,
                    wordCount: 1,
                    segmentation: .sentenceGroup,
                ),
            ] : chunks
        }()

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for plannedChunk in plannedChunks {
                        try Task.checkCancellation()

                        let startedAt = Date()
                        var sawFirstAudio = false
                        var audioChunkCount = 0
                        var sampleCount = 0

                        await logQwenLiveChunkStarted(
                            requestID: requestID,
                            op: op,
                            profileName: profileName,
                            chunk: plannedChunk,
                            totalChunkCount: plannedChunks.count,
                            streamingInterval: streamingInterval,
                        )

                        let eventStream = model.generateConditionedEventStream(
                            text: plannedChunk.text,
                            conditioning: conditioning,
                            generationParameters: generationParameters,
                            streamingInterval: streamingInterval,
                        )

                        for try await event in eventStream {
                            switch event {
                                case let .token(token):
                                    recordGenerationEvent(.token(token), for: requestID)
                                case let .info(info):
                                    recordGenerationEvent(.info(generationEventInfo(from: info)), for: requestID)
                                case let .audio(samples):
                                    audioChunkCount += 1
                                    sampleCount += samples.count
                                    recordGenerationEvent(.audioChunk(sampleCount: samples.count), for: requestID)
                                    if !sawFirstAudio {
                                        sawFirstAudio = true
                                        await logQwenLiveChunkFirstAudio(
                                            requestID: requestID,
                                            op: op,
                                            profileName: profileName,
                                            chunk: plannedChunk,
                                            totalChunkCount: plannedChunks.count,
                                            timeToFirstAudioMS: Int((Date().timeIntervalSince(startedAt) * 1000).rounded()),
                                            sampleCount: samples.count,
                                        )
                                    }
                                    continuation.yield(samples)
                            }
                        }

                        await logQwenLiveChunkFinished(
                            requestID: requestID,
                            op: op,
                            profileName: profileName,
                            chunk: plannedChunk,
                            totalChunkCount: plannedChunks.count,
                            elapsedMS: Int((Date().timeIntervalSince(startedAt) * 1000).rounded()),
                            audioChunkCount: audioChunkCount,
                            sampleCount: sampleCount,
                        )
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
