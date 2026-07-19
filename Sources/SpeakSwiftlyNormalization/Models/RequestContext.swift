import Foundation
import SpeakSwiftlyCore

public extension SpeakSwiftlyNormalization {
    typealias RequestContext = SpeakSwiftlyCore.RequestContext
}

extension SpeakSwiftlyNormalization.RequestContext {
    var speechPreface: String? {
        guard shouldPreface else { return nil }

        let normalizedSource = normalizedMetadata(source)
        let normalizedTopic = normalizedMetadata(topic)

        return switch (normalizedSource, normalizedTopic) {
            case let (source?, topic?):
                "From \(source), \(topic)."
            case let (source?, nil):
                "From \(source)."
            case let (nil, topic?):
                "About \(topic)."
            case (nil, nil):
                nil
        }
    }

    func prefacing(_ text: String) -> String {
        guard let speechPreface else { return text }
        guard !text.isEmpty else { return speechPreface }

        return "\(speechPreface)\n\n\(text)"
    }

    private var shouldPreface: Bool {
        switch prefacePolicy ?? .default {
            case .always:
                true
            case .never:
                false
            case .default:
                switch reqPurpose {
                    case .speech:
                        true
                    case .audioFile:
                        false
                }
        }
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}
