extension TextNormalizer {
    static func detectTextFormat(in text: String) -> SpeakSwiftlyNormalization.TextFormat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .plain }

        if looksLikeHTML(trimmed) {
            return .html
        }

        if looksLikeMarkdownList(trimmed) {
            return .list
        }

        if looksLikeMarkdown(trimmed) {
            return .markdown
        }

        if looksLikeCLIOutput(trimmed) {
            return .cli
        }

        if looksLikeLogOutput(trimmed) {
            return .log
        }

        return .plain
    }
}
