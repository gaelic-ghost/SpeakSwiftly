import Testing
import SpeakSwiftly

@Test func publicLibrarySurfaceConstructsLiveRuntime() async {
    _ = await SpeakSwiftly.makeLiveRuntime()
}
