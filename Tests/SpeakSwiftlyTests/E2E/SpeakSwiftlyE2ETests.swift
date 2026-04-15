import Testing

@Suite(
    .serialized,
    .enabled(
        if: speakSwiftlyE2ETestsEnabled(),
        "These end-to-end worker tests are opt-in and require SPEAKSWIFTLY_E2E=1.",
    ),
)
enum SpeakSwiftlyE2ETests {}
