extension PlaybackQueue {
    struct ConcurrencyAdmissionThresholds {
        let startupBufferTargetMS: Int
        let concurrentGenerationTargetMS: Int
    }

    struct FragileOverlapWindowConfiguration: Equatable {
        let holdBufferTargetMS: Int
        let requiredStableBufferEventCount: Int
    }

    struct FragileOverlapWindowProgress: Equatable {
        let configuration: FragileOverlapWindowConfiguration
        var stableBufferEventCount: Int
        var hasSatisfiedHold: Bool
    }

    struct ConcurrencyAdmissionResolution: Equatable {
        let allowsConcurrentGeneration: Bool
        let effectiveTargetMS: Int
        let fragileOverlapWindowProgress: FragileOverlapWindowProgress?
    }

    struct ConcurrencySnapshot: Equatable {
        let activeRequestID: String?
        let isStableForConcurrentGeneration: Bool
        let stableBufferedAudioMS: Int?
        let stableBufferTargetMS: Int?
        let isRebuffering: Bool
    }

    struct GenerationAdmissionSnapshot: Equatable {
        let activeRequestID: String?
        let allowsConcurrentGeneration: Bool
    }

    static func concurrencyAdmissionThresholds(
        startupBufferTargetMS: Int,
    ) -> ConcurrencyAdmissionThresholds {
        ConcurrencyAdmissionThresholds(
            startupBufferTargetMS: startupBufferTargetMS,
            concurrentGenerationTargetMS: startupBufferTargetMS,
        )
    }

    static func allowsConcurrentGeneration(
        bufferedAudioMS: Int,
        targetMS: Int,
    ) -> Bool {
        bufferedAudioMS >= targetMS
    }

    static func resolveConcurrentGenerationAdmission(
        bufferedAudioMS: Int,
        concurrentGenerationTargetMS: Int,
        fragileOverlapWindowProgress: FragileOverlapWindowProgress?,
    ) -> ConcurrencyAdmissionResolution {
        guard var fragileOverlapWindowProgress else {
            return ConcurrencyAdmissionResolution(
                allowsConcurrentGeneration: allowsConcurrentGeneration(
                    bufferedAudioMS: bufferedAudioMS,
                    targetMS: concurrentGenerationTargetMS,
                ),
                effectiveTargetMS: concurrentGenerationTargetMS,
                fragileOverlapWindowProgress: nil,
            )
        }

        let fragileTargetMS = fragileOverlapWindowProgress.configuration.holdBufferTargetMS

        if fragileOverlapWindowProgress.hasSatisfiedHold {
            if bufferedAudioMS < fragileTargetMS {
                fragileOverlapWindowProgress.hasSatisfiedHold = false
                fragileOverlapWindowProgress.stableBufferEventCount = 0
                return ConcurrencyAdmissionResolution(
                    allowsConcurrentGeneration: false,
                    effectiveTargetMS: fragileTargetMS,
                    fragileOverlapWindowProgress: fragileOverlapWindowProgress,
                )
            }

            return ConcurrencyAdmissionResolution(
                allowsConcurrentGeneration: true,
                effectiveTargetMS: concurrentGenerationTargetMS,
                fragileOverlapWindowProgress: fragileOverlapWindowProgress,
            )
        }

        if bufferedAudioMS >= fragileTargetMS {
            fragileOverlapWindowProgress.stableBufferEventCount += 1
        } else {
            fragileOverlapWindowProgress.stableBufferEventCount = 0
        }

        if fragileOverlapWindowProgress.stableBufferEventCount >= fragileOverlapWindowProgress.configuration.requiredStableBufferEventCount {
            fragileOverlapWindowProgress.hasSatisfiedHold = true
            return ConcurrencyAdmissionResolution(
                allowsConcurrentGeneration: true,
                effectiveTargetMS: concurrentGenerationTargetMS,
                fragileOverlapWindowProgress: fragileOverlapWindowProgress,
            )
        }

        return ConcurrencyAdmissionResolution(
            allowsConcurrentGeneration: false,
            effectiveTargetMS: fragileTargetMS,
            fragileOverlapWindowProgress: fragileOverlapWindowProgress,
        )
    }

    func coordinationTelemetrySnapshot() -> ConcurrencySnapshot {
        ConcurrencySnapshot(
            activeRequestID: activePlayback?.requestID,
            isStableForConcurrentGeneration: activePlaybackIsStableForConcurrentGeneration,
            stableBufferedAudioMS: activePlaybackStableBufferedAudioMS,
            stableBufferTargetMS: activePlaybackStableBufferTargetMS,
            isRebuffering: activePlaybackIsRebuffering,
        )
    }

    func generationAdmissionSnapshot() -> GenerationAdmissionSnapshot {
        GenerationAdmissionSnapshot(
            activeRequestID: activePlayback?.requestID,
            allowsConcurrentGeneration: activePlayback == nil || activePlaybackIsStableForConcurrentGeneration,
        )
    }

    func recordConcurrencyEvent(_ event: PlaybackEvent, for requestID: String) {
        guard activePlayback?.requestID == requestID else { return }

        switch event {
            case let .prerollReady(startupBufferedAudioMS, thresholds):
                let admissionThresholds = Self.concurrencyAdmissionThresholds(
                    startupBufferTargetMS: thresholds.startupBufferTargetMS,
                )
                activePlaybackConcurrentGenerationTargetMS = admissionThresholds.concurrentGenerationTargetMS
                activePlaybackFragileOverlapWindowProgress = nil
                applyConcurrentGenerationAdmission(
                    bufferedAudioMS: startupBufferedAudioMS,
                    concurrentGenerationTargetMS: admissionThresholds.concurrentGenerationTargetMS,
                )
                activePlaybackIsRebuffering = false
            case .rebufferStarted:
                activePlaybackIsStableForConcurrentGeneration = false
                if var fragileOverlapWindowProgress = activePlaybackFragileOverlapWindowProgress {
                    fragileOverlapWindowProgress.hasSatisfiedHold = false
                    fragileOverlapWindowProgress.stableBufferEventCount = 0
                    activePlaybackFragileOverlapWindowProgress = fragileOverlapWindowProgress
                    activePlaybackStableBufferTargetMS = fragileOverlapWindowProgress.configuration.holdBufferTargetMS
                }
                activePlaybackIsRebuffering = true
            case let .rebufferResumed(bufferedAudioMS, thresholds):
                activePlaybackConcurrentGenerationTargetMS = thresholds.resumeBufferTargetMS
                applyConcurrentGenerationAdmission(
                    bufferedAudioMS: bufferedAudioMS,
                    concurrentGenerationTargetMS: thresholds.resumeBufferTargetMS,
                )
                activePlaybackIsRebuffering = false
            case .starved:
                activePlaybackIsStableForConcurrentGeneration = false
                if var fragileOverlapWindowProgress = activePlaybackFragileOverlapWindowProgress {
                    fragileOverlapWindowProgress.hasSatisfiedHold = false
                    fragileOverlapWindowProgress.stableBufferEventCount = 0
                    activePlaybackFragileOverlapWindowProgress = fragileOverlapWindowProgress
                    activePlaybackStableBufferTargetMS = fragileOverlapWindowProgress.configuration.holdBufferTargetMS
                }
                activePlaybackIsRebuffering = true
            case let .trace(trace):
                guard
                    trace.name == "buffer_scheduled",
                    !activePlaybackIsStableForConcurrentGeneration,
                    !activePlaybackIsRebuffering,
                    let queuedAudioAfterMS = trace.queuedAudioAfterMS,
                    let concurrentGenerationTargetMS = activePlaybackConcurrentGenerationTargetMS
                else {
                    if
                        trace.name == "buffer_scheduled",
                        !activePlaybackIsRebuffering,
                        let queuedAudioAfterMS = trace.queuedAudioAfterMS,
                        let concurrentGenerationTargetMS = activePlaybackConcurrentGenerationTargetMS {
                        applyConcurrentGenerationAdmission(
                            bufferedAudioMS: queuedAudioAfterMS,
                            concurrentGenerationTargetMS: concurrentGenerationTargetMS,
                        )
                    }
                    break
                }

                applyConcurrentGenerationAdmission(
                    bufferedAudioMS: queuedAudioAfterMS,
                    concurrentGenerationTargetMS: concurrentGenerationTargetMS,
                )
            case .firstChunk,
                 .queueDepthLow,
                 .chunkGapWarning,
                 .scheduleGapWarning,
                 .rebufferThrashWarning,
                 .generationQualityWarning,
                 .outputDeviceChanged,
                 .engineConfigurationChanged,
                 .bufferShapeSummary:
                break
        }
    }

    private func applyConcurrentGenerationAdmission(
        bufferedAudioMS: Int,
        concurrentGenerationTargetMS: Int,
    ) {
        let resolution = Self.resolveConcurrentGenerationAdmission(
            bufferedAudioMS: bufferedAudioMS,
            concurrentGenerationTargetMS: concurrentGenerationTargetMS,
            fragileOverlapWindowProgress: activePlaybackFragileOverlapWindowProgress,
        )
        activePlaybackStableBufferedAudioMS = bufferedAudioMS
        activePlaybackStableBufferTargetMS = resolution.effectiveTargetMS
        activePlaybackIsStableForConcurrentGeneration = resolution.allowsConcurrentGeneration
        activePlaybackFragileOverlapWindowProgress = resolution.fragileOverlapWindowProgress
    }
}
