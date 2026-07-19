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
            isStableForConcurrentGeneration: activePlayback?.isStableForConcurrentGeneration ?? false,
            stableBufferedAudioMS: activePlayback?.stableBufferedAudioMS,
            stableBufferTargetMS: activePlayback?.stableBufferTargetMS,
            isRebuffering: activePlayback?.isRebuffering ?? false,
        )
    }

    func generationAdmissionSnapshot() -> GenerationAdmissionSnapshot {
        GenerationAdmissionSnapshot(
            activeRequestID: activePlayback?.requestID,
            allowsConcurrentGeneration: activePlayback == nil
                || activePlayback?.isStableForConcurrentGeneration == true,
        )
    }

    func recordConcurrencyEvent(_ event: PlaybackEvent, for requestID: String) {
        guard var activePlayback, activePlayback.requestID == requestID else { return }

        switch event {
            case let .prerollReady(startupBufferedAudioMS, thresholds):
                let admissionThresholds = Self.concurrencyAdmissionThresholds(
                    startupBufferTargetMS: thresholds.startupBufferTargetMS,
                )
                activePlayback.concurrentGenerationTargetMS = admissionThresholds.concurrentGenerationTargetMS
                activePlayback.fragileOverlapWindowProgress = nil
                applyConcurrentGenerationAdmission(
                    bufferedAudioMS: startupBufferedAudioMS,
                    concurrentGenerationTargetMS: admissionThresholds.concurrentGenerationTargetMS,
                    activePlayback: &activePlayback,
                )
                activePlayback.isRebuffering = false
            case .rebufferStarted:
                activePlayback.resetFragileOverlapWindowAfterDistress()
                activePlayback.isRebuffering = true
            case let .rebufferResumed(bufferedAudioMS, thresholds):
                activePlayback.concurrentGenerationTargetMS = thresholds.resumeBufferTargetMS
                applyConcurrentGenerationAdmission(
                    bufferedAudioMS: bufferedAudioMS,
                    concurrentGenerationTargetMS: thresholds.resumeBufferTargetMS,
                    activePlayback: &activePlayback,
                )
                activePlayback.isRebuffering = false
            case .starved:
                activePlayback.resetFragileOverlapWindowAfterDistress()
                activePlayback.isRebuffering = true
            case let .trace(trace):
                guard
                    trace.name == "buffer_scheduled",
                    !activePlayback.isStableForConcurrentGeneration,
                    !activePlayback.isRebuffering,
                    let queuedAudioAfterMS = trace.queuedAudioAfterMS,
                    let concurrentGenerationTargetMS = activePlayback.concurrentGenerationTargetMS
                else {
                    if
                        trace.name == "buffer_scheduled",
                        !activePlayback.isRebuffering,
                        let queuedAudioAfterMS = trace.queuedAudioAfterMS,
                        let concurrentGenerationTargetMS = activePlayback.concurrentGenerationTargetMS {
                        applyConcurrentGenerationAdmission(
                            bufferedAudioMS: queuedAudioAfterMS,
                            concurrentGenerationTargetMS: concurrentGenerationTargetMS,
                            activePlayback: &activePlayback,
                        )
                    }
                    break
                }

                applyConcurrentGenerationAdmission(
                    bufferedAudioMS: queuedAudioAfterMS,
                    concurrentGenerationTargetMS: concurrentGenerationTargetMS,
                    activePlayback: &activePlayback,
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

        self.activePlayback = activePlayback
    }

    private func applyConcurrentGenerationAdmission(
        bufferedAudioMS: Int,
        concurrentGenerationTargetMS: Int,
        activePlayback: inout ActivePlayback,
    ) {
        let resolution = Self.resolveConcurrentGenerationAdmission(
            bufferedAudioMS: bufferedAudioMS,
            concurrentGenerationTargetMS: concurrentGenerationTargetMS,
            fragileOverlapWindowProgress: activePlayback.fragileOverlapWindowProgress,
        )
        activePlayback.stableBufferedAudioMS = bufferedAudioMS
        activePlayback.stableBufferTargetMS = resolution.effectiveTargetMS
        activePlayback.isStableForConcurrentGeneration = resolution.allowsConcurrentGeneration
        activePlayback.fragileOverlapWindowProgress = resolution.fragileOverlapWindowProgress
    }
}
