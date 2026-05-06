import TextForSpeech

public extension SpeakSwiftly {
    /// A stable operator-facing name used for stored resources such as voice profiles.
    typealias Name = String

    /// A stable identifier for one stored text-normalization profile.
    typealias TextProfileID = String

    /// Describes where a generation request came from and what it is related to.
    ///
    /// `TextForSpeech` owns the concrete model so request metadata stays identical
    /// across normalization, generation, and downstream server surfaces.
    typealias RequestContext = TextForSpeech.RequestContext
}
