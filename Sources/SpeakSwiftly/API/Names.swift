import SpeakSwiftlyCore
import SpeakSwiftlyNormalization

public extension SpeakSwiftly {
    /// A stable operator-facing name used for stored resources such as voice profiles.
    typealias Name = String

    /// A stable identifier for one stored text-normalization profile.
    typealias TextProfileID = String

    /// Describes where a generation request came from and what it is related to.
    typealias RequestContext = SpeakSwiftlyCore.RequestContext

    /// The detected structure of ordinary text before speech-safe normalization.
    typealias TextFormat = SpeakSwiftlyCore.TextFormat

    /// The programming-language family used for whole-source normalization.
    typealias SourceFormat = SpeakSwiftlyCore.SourceFormat

    /// The package-provided normalization posture applied before custom rules.
    typealias TextProfileStyle = SpeakSwiftlyNormalization.BuiltInProfileStyle

    /// One typed text-replacement rule in a stored text profile.
    typealias TextReplacement = SpeakSwiftlyNormalization.Replacement

    /// One composable text-normalization profile.
    typealias TextProfile = SpeakSwiftlyNormalization.Profile

    /// A persisted snapshot of the complete text-normalization state.
    typealias TextNormalizationState = SpeakSwiftlyNormalization.PersistedState

    /// The backend used when a normalization request asks for summarization.
    typealias SummarizationProvider = SpeakSwiftlyNormalization.SummarizationProvider

    /// A human-readable stored text-profile summary.
    typealias TextProfileSummary = SpeakSwiftlyNormalization.TextProfileSummary

    /// The complete public representation of one stored text profile.
    typealias TextProfileDetails = SpeakSwiftlyNormalization.TextProfileDetails

    /// A selectable package-provided text-profile style.
    typealias TextProfileStyleOption = SpeakSwiftlyNormalization.TextProfileStyleOption

    /// A selectable summarization backend and its operator-facing description.
    typealias SummarizationProviderOption = SpeakSwiftlyNormalization.SummarizationProviderOption

    /// Errors raised while mutating stored text profiles.
    typealias TextProfileError = SpeakSwiftlyNormalization.ProfileError

    /// Errors raised while reading or writing text-normalization state.
    typealias TextNormalizationPersistenceError = SpeakSwiftlyNormalization.PersistenceError
}
