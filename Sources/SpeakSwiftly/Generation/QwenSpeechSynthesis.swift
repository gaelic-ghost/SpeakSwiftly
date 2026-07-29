import Foundation
@preconcurrency import MLX
import MLXAudioTTS
@preconcurrency import MLXLMCommon

// MARK: - Qwen Speech Synthesis

extension SpeakSwiftly.Runtime {
    enum QwenGenerationReference {
        case raw(
            materialization: StoredProfileMaterialization,
            refAudio: MLXArray?,
        )
        case prepared(Qwen3TTSModel.Qwen3TTSReferenceConditioning)
    }

    struct QwenLiveChunkAccounting {
        let startedAt = Date()
        private(set) var sawFirstAudio = false
        private(set) var audioChunkCount = 0
        private(set) var sampleCount = 0

        mutating func recordAudioChunk(_ samples: [Float]) -> Bool {
            audioChunkCount += 1
            sampleCount += samples.count

            if sawFirstAudio {
                return false
            }

            sawFirstAudio = true
            return true
        }

        func elapsedMS(now: Date = Date()) -> Int {
            Int((now.timeIntervalSince(startedAt) * 1000).rounded())
        }
    }

    func synthesisEventInfo(from info: ModelGenerationEvent.Info) -> SpeakSwiftly.SynthesisEventInfo {
        SpeakSwiftly.SynthesisEventInfo(
            promptTokenCount: info.promptTokenCount,
            generationTokenCount: info.generationTokenCount,
            prefillTime: info.prefillTime,
            generateTime: info.generateTime,
            tokensPerSecond: info.tokensPerSecond,
            peakMemoryUsage: info.peakMemoryUsage,
        )
    }

    private func defaultLiveSpeechTextChunks(for text: String) -> [LiveSpeechTextChunk] {
        [
            LiveSpeechTextChunk(
                index: 1,
                text: text,
                wordCount: max(SpeakSwiftly.DeepTrace.words(in: text).count, 1),
                segmentation: .sentenceGroup,
            ),
        ]
    }

    private func qwenEventStream(
        model: AnySpeechModel,
        text: String,
        reference: QwenGenerationReference,
        generationParameters: GenerateParameters,
        streamingInterval: Double,
    ) -> AsyncThrowingStream<ModelGenerationEvent, Error> {
        switch reference {
            case let .raw(materialization, refAudio):
                model.generateEventStream(
                    text: text,
                    voice: nil,
                    refAudio: refAudio,
                    refText: materialization.manifest.referenceText,
                    language: nil,
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )

            case let .prepared(conditioning):
                model.generateConditionedEventStream(
                    text: text,
                    conditioning: conditioning,
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )
        }
    }

    private func recordQwenGenerationEvent(
        _ event: ModelGenerationEvent,
        requestID: String,
    ) -> [Float]? {
        switch event {
            case let .token(token):
                recordSynthesisEvent(.token(token), for: requestID)
                return nil
            case let .info(info):
                recordSynthesisEvent(.info(synthesisEventInfo(from: info)), for: requestID)
                return nil
            case let .audio(samples):
                recordSynthesisEvent(.audioChunk(sampleCount: samples.count), for: requestID)
                return samples
        }
    }

    func qwenGenerationStream(
        requestID: String,
        op: String?,
        profileName: String,
        model: AnySpeechModel,
        text: String,
        reference: QwenGenerationReference,
        generationParameters: GenerateParameters,
        streamingInterval: Double,
    ) -> AsyncThrowingStream<[Float], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
#if DEBUG
                var diagnostics = QwenGenerationDiagnostics(reference: reference)
                await logRequestEvent(
                    "qwen_generation_debug_started",
                    requestID: requestID,
                    op: op,
                    profileName: profileName,
                    details: diagnostics.startedDetails(
                        generationParameters: generationParameters,
                        text: text,
                        chunkIndex: nil,
                    ),
                )
#endif
                do {
                    let eventStream = qwenEventStream(
                        model: model,
                        text: text,
                        reference: reference,
                        generationParameters: generationParameters,
                        streamingInterval: streamingInterval,
                    )
                    for try await event in eventStream {
                        try Task.checkCancellation()
#if DEBUG
                        diagnostics.record(event)
#endif
                        if let samples = recordQwenGenerationEvent(event, requestID: requestID) {
                            continuation.yield(samples)
                        }
                    }
#if DEBUG
                    await logRequestEvent(
                        "qwen_generation_debug_finished",
                        requestID: requestID,
                        op: op,
                        profileName: profileName,
                        details: diagnostics.finishedDetails(
                            reference: reference,
                            outcome: "completed",
                            chunkIndex: nil,
                        ),
                    )
#endif
                    continuation.finish()
                } catch is CancellationError {
#if DEBUG
                    await logRequestEvent(
                        "qwen_generation_debug_finished",
                        requestID: requestID,
                        op: op,
                        profileName: profileName,
                        details: diagnostics.finishedDetails(
                            reference: reference,
                            outcome: "cancelled",
                            chunkIndex: nil,
                        ),
                    )
#endif
                    continuation.finish(throwing: CancellationError())
                } catch {
#if DEBUG
                    await logRequestEvent(
                        "qwen_generation_debug_finished",
                        requestID: requestID,
                        op: op,
                        profileName: profileName,
                        details: diagnostics.finishedDetails(
                            reference: reference,
                            outcome: "failed",
                            chunkIndex: nil,
                        ),
                    )
#endif
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
        reference: QwenGenerationReference,
        generationParameters: GenerateParameters,
        streamingInterval: Double,
    ) -> AsyncThrowingStream<[Float], Error> {
        let plannedChunks = plannedChunks ?? defaultLiveSpeechTextChunks(for: text)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for plannedChunk in plannedChunks {
                        try Task.checkCancellation()

                        var accounting = QwenLiveChunkAccounting()
#if DEBUG
                        var diagnostics = QwenGenerationDiagnostics(reference: reference)
                        await logRequestEvent(
                            "qwen_generation_debug_started",
                            requestID: requestID,
                            op: op,
                            profileName: profileName,
                            details: diagnostics.startedDetails(
                                generationParameters: generationParameters,
                                text: plannedChunk.text,
                                chunkIndex: plannedChunk.index,
                            ),
                        )
#endif

                        await logQwenLiveChunkStarted(
                            requestID: requestID,
                            op: op,
                            profileName: profileName,
                            chunk: plannedChunk,
                            totalChunkCount: plannedChunks.count,
                            streamingInterval: streamingInterval,
                        )

                        do {
                            let eventStream = qwenEventStream(
                                model: model,
                                text: plannedChunk.text,
                                reference: reference,
                                generationParameters: generationParameters,
                                streamingInterval: streamingInterval,
                            )

                            for try await event in eventStream {
                                try Task.checkCancellation()
#if DEBUG
                                diagnostics.record(event)
#endif

                                if let samples = recordQwenGenerationEvent(event, requestID: requestID) {
                                    if accounting.recordAudioChunk(samples) {
                                        await logQwenLiveChunkFirstAudio(
                                            requestID: requestID,
                                            op: op,
                                            profileName: profileName,
                                            chunk: plannedChunk,
                                            totalChunkCount: plannedChunks.count,
                                            timeToFirstAudioMS: accounting.elapsedMS(),
                                            sampleCount: samples.count,
                                        )
                                    }
                                    continuation.yield(samples)
                                }
                            }

#if DEBUG
                            await logRequestEvent(
                                "qwen_generation_debug_finished",
                                requestID: requestID,
                                op: op,
                                profileName: profileName,
                                details: diagnostics.finishedDetails(
                                    reference: reference,
                                    outcome: "completed",
                                    chunkIndex: plannedChunk.index,
                                ),
                            )
#endif
                        } catch is CancellationError {
#if DEBUG
                            await logRequestEvent(
                                "qwen_generation_debug_finished",
                                requestID: requestID,
                                op: op,
                                profileName: profileName,
                                details: diagnostics.finishedDetails(
                                    reference: reference,
                                    outcome: "cancelled",
                                    chunkIndex: plannedChunk.index,
                                ),
                            )
#endif
                            throw CancellationError()
                        } catch {
#if DEBUG
                            await logRequestEvent(
                                "qwen_generation_debug_finished",
                                requestID: requestID,
                                op: op,
                                profileName: profileName,
                                details: diagnostics.finishedDetails(
                                    reference: reference,
                                    outcome: "failed",
                                    chunkIndex: plannedChunk.index,
                                ),
                            )
#endif
                            throw error
                        }

                        await logQwenLiveChunkFinished(
                            requestID: requestID,
                            op: op,
                            profileName: profileName,
                            chunk: plannedChunk,
                            totalChunkCount: plannedChunks.count,
                            elapsedMS: accounting.elapsedMS(),
                            audioChunkCount: accounting.audioChunkCount,
                            sampleCount: accounting.sampleCount,
                        )

                        if plannedChunk.index < plannedChunks.count {
                            continuation.yield([])
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
}
