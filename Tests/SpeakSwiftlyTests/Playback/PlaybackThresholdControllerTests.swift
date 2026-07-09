@testable import SpeakSwiftly
import Testing

@Test func `adaptive playback thresholds seed from text complexity classes`() {
    let compact = PlaybackThresholdController(text: "Hello there.").thresholds
    let balanced = PlaybackThresholdController(
        text: String(repeating: "This is ordinary spoken prose for playback buffering. ", count: 7),
    ).thresholds
    let extended = PlaybackThresholdController(
        text: String(
            repeating: "This is a deliberately long spoken paragraph used to seed playback buffering from length alone. ",
            count: 9,
        ),
    ).thresholds

    #expect(compact.complexityClass == .compact)
    #expect(balanced.complexityClass == .balanced)
    #expect(extended.complexityClass == .extended)
    #expect(compact.startupBufferTargetMS < balanced.startupBufferTargetMS)
    #expect(balanced.startupBufferTargetMS < extended.startupBufferTargetMS)
    #expect(compact.resumeBufferTargetMS < balanced.resumeBufferTargetMS)
    #expect(balanced.resumeBufferTargetMS < extended.resumeBufferTargetMS)
}

@Test func `adaptive playback thresholds start from warmup biased targets`() {
    let compact = PlaybackThresholdController(text: "Hello there.").thresholds
    let balanced = PlaybackThresholdController(
        text: String(repeating: "This is ordinary spoken prose for playback buffering. ", count: 7),
    ).thresholds
    let extended = PlaybackThresholdController(
        text: String(
            repeating: "This is a deliberately long spoken paragraph used to seed playback buffering from length alone. ",
            count: 9,
        ),
    ).thresholds

    #expect(compact.startupBufferTargetMS == 480)
    #expect(compact.lowWaterTargetMS == 220)
    #expect(compact.resumeBufferTargetMS == 540)
    #expect(balanced.startupBufferTargetMS == 720)
    #expect(balanced.lowWaterTargetMS == 340)
    #expect(balanced.resumeBufferTargetMS == 800)
    #expect(extended.startupBufferTargetMS == 13120)
    #expect(extended.lowWaterTargetMS == 5000)
    #expect(extended.resumeBufferTargetMS == 16480)
}

@Test func `adaptive playback thresholds ignore content shape when lengths match`() {
    let plainText = String(repeating: "Please explain this clearly. ", count: 8)
    let codeishSeed = """
    /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/WorkerRuntime.swift
    user?.displayName ?? defaults["voice_profile"]
    NSApplication.didFinishLaunchingNotification
    """
    let paddedCodeishText = codeishSeed + String(repeating: ".", count: max(0, plainText.count - codeishSeed.count))

    let plain = PlaybackThresholdController(text: plainText).thresholds
    let codeish = PlaybackThresholdController(text: paddedCodeishText).thresholds

    #expect(plain.complexityClass == codeish.complexityClass)
    #expect(plain.startupBufferTargetMS == codeish.startupBufferTargetMS)
    #expect(plain.lowWaterTargetMS == codeish.lowWaterTargetMS)
    #expect(plain.resumeBufferTargetMS == codeish.resumeBufferTargetMS)
    #expect(plain.chunkGapWarningMS == codeish.chunkGapWarningMS)
    #expect(plain.scheduleGapWarningMS == codeish.scheduleGapWarningMS)
}

@Test func `adaptive playback thresholds raise targets for slow cadence and starvation`() {
    var controller = PlaybackThresholdController(text: "Hello there.")
    let seeded = controller.thresholds

    for _ in 0..<4 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 315)
    }
    let adapted = controller.thresholds
    controller.recordStarvation()
    let starved = controller.thresholds

    #expect(adapted.startupBufferTargetMS > seeded.startupBufferTargetMS)
    #expect(adapted.lowWaterTargetMS > seeded.lowWaterTargetMS)
    #expect(adapted.resumeBufferTargetMS > seeded.resumeBufferTargetMS)
    #expect(starved.resumeBufferTargetMS >= adapted.resumeBufferTargetMS)
    #expect(starved.startupBufferTargetMS >= starved.resumeBufferTargetMS)
    #expect(starved.lowWaterTargetMS >= adapted.lowWaterTargetMS)
}

@Test func `adaptive playback thresholds raise targets for repeated rebuffers`() {
    var controller = PlaybackThresholdController(
        text: """
        Please read this file path and code-heavy explanation carefully.
        /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/WorkerRuntime.swift
        let greeting = user?.displayName ?? "friend"
        """,
    )

    for _ in 0..<6 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 205)
    }

    let adapted = controller.thresholds
    controller.recordRebuffer()
    let afterFirstRebuffer = controller.thresholds
    controller.recordRebuffer()
    let afterSecondRebuffer = controller.thresholds
    controller.recordRebuffer()
    let afterThirdRebuffer = controller.thresholds

    #expect(afterFirstRebuffer == adapted)
    #expect(afterSecondRebuffer.startupBufferTargetMS > adapted.startupBufferTargetMS)
    #expect(afterSecondRebuffer.lowWaterTargetMS > adapted.lowWaterTargetMS)
    #expect(afterSecondRebuffer.resumeBufferTargetMS > adapted.resumeBufferTargetMS)
    #expect(afterSecondRebuffer.chunkGapWarningMS >= adapted.chunkGapWarningMS)
    #expect(afterSecondRebuffer.scheduleGapWarningMS >= adapted.scheduleGapWarningMS)
    #expect(afterThirdRebuffer.resumeBufferTargetMS > afterSecondRebuffer.resumeBufferTargetMS)
}

@Test func `adaptive playback thresholds keep escalated rebuffer targets across later chunks`() {
    var controller = PlaybackThresholdController(
        text: """
        Please read this code-heavy diagnostic trace.
        /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/PlaybackQueue.swift
        let greeting = user?.displayName ?? "friend"
        """,
    )

    for _ in 0..<6 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 205)
    }

    controller.recordRebuffer()
    controller.recordRebuffer()
    let escalated = controller.thresholds

    for _ in 0..<6 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 182)
    }

    let afterMoreChunks = controller.thresholds

    #expect(afterMoreChunks.startupBufferTargetMS >= escalated.startupBufferTargetMS)
    #expect(afterMoreChunks.lowWaterTargetMS >= escalated.lowWaterTargetMS)
    #expect(afterMoreChunks.resumeBufferTargetMS >= escalated.resumeBufferTargetMS)
    #expect(afterMoreChunks.chunkGapWarningMS >= escalated.chunkGapWarningMS)
    #expect(afterMoreChunks.scheduleGapWarningMS >= escalated.scheduleGapWarningMS)
}

@Test func `pre-rebuffer schedule gap hardening ignores low-risk queued audio`() {
    var controller = PlaybackThresholdController(text: String(repeating: "This is ordinary spoken prose for playback buffering. ", count: 7))

    for _ in 0..<6 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 205)
    }

    let adapted = controller.thresholds
    controller.recordScheduleGapDistress(gapMS: 460, queuedAudioMS: 6400)
    controller.recordScheduleGapDistress(gapMS: 460, queuedAudioMS: 6000)

    #expect(controller.phase == .warmup)
    #expect(controller.thresholds == adapted)
}

@Test func `adaptive playback thresholds leave warmup after stable chunk cadence`() {
    var controller = PlaybackThresholdController(
        text: """
        Please read this code-heavy diagnostic trace.
        /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/PlaybackQueue.swift
        let greeting = user?.displayName ?? "friend"
        """,
    )

    #expect(controller.phase == .warmup)

    for _ in 0..<12 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 182)
    }

    #expect(controller.phase == .steady)
}

@Test func `adaptive playback thresholds stay in warmup while early cadence trails realtime playback`() {
    var controller = PlaybackThresholdController(
        text: String(
            repeating: "This is ordinary spoken prose for playback buffering. ",
            count: 7,
        ),
    )

    #expect(controller.phase == .warmup)

    for _ in 0..<7 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 250)
    }

    #expect(controller.phase == .warmup)
    #expect(controller.thresholds.startupBufferTargetMS >= 1600)
    #expect(controller.thresholds.lowWaterTargetMS >= 600)
    #expect(controller.thresholds.resumeBufferTargetMS >= 1400)
}

@Test func `adaptive playback thresholds enter recovery after rebuffer and return to steady after stable chunks`() {
    var controller = PlaybackThresholdController(
        text: """
        Please read this code-heavy diagnostic trace.
        /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/PlaybackQueue.swift
        let greeting = user?.displayName ?? "friend"
        """,
    )

    for _ in 0..<12 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 182)
    }
    #expect(controller.phase == .steady)

    controller.recordRebuffer()
    #expect(controller.phase == .recovery)

    for _ in 0..<8 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 184)
    }

    #expect(controller.phase == .steady)
}
