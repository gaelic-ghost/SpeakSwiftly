import Foundation

extension TextNormalizer {
    struct CurrencyDefinition {
        let singular: String
        let plural: String
        let minorSingular: String?
        let minorPlural: String?
        let decimalJoiner: String
    }

    struct MeasurementDefinition {
        let singular: String
        let plural: String
    }

    struct ParsedCurrencyAmount {
        let definition: CurrencyDefinition
        let wholePart: String
        let fractionalPart: String?
    }

    struct ParsedMeasuredValue {
        let numericPart: String
        let definition: MeasurementDefinition
    }

    private static let currencyDefinitions: [Character: CurrencyDefinition] = [
        "$": CurrencyDefinition(
            singular: "dollar",
            plural: "dollars",
            minorSingular: "cent",
            minorPlural: "cents",
            decimalJoiner: " and ",
        ),
        "£": CurrencyDefinition(
            singular: "pound",
            plural: "pounds",
            minorSingular: nil,
            minorPlural: nil,
            decimalJoiner: ", ",
        ),
        "€": CurrencyDefinition(
            singular: "euro",
            plural: "euros",
            minorSingular: "cent",
            minorPlural: "cents",
            decimalJoiner: " and ",
        ),
    ]

    private static let measurementDefinitions: [String: MeasurementDefinition] = [
        "km": MeasurementDefinition(singular: "kilometer", plural: "kilometers"),
        "mi": MeasurementDefinition(singular: "mile", plural: "miles"),
        "kg": MeasurementDefinition(singular: "kilogram", plural: "kilograms"),
        "in": MeasurementDefinition(singular: "inch", plural: "inches"),
        "KBps": MeasurementDefinition(singular: "kilobyte per second", plural: "kilobytes per second"),
        "KB/s": MeasurementDefinition(singular: "kilobyte per second", plural: "kilobytes per second"),
        "Kbps": MeasurementDefinition(singular: "kilobit per second", plural: "kilobits per second"),
        "kbps": MeasurementDefinition(singular: "kilobit per second", plural: "kilobits per second"),
        "Kb/s": MeasurementDefinition(singular: "kilobit per second", plural: "kilobits per second"),
        "MBps": MeasurementDefinition(singular: "megabyte per second", plural: "megabytes per second"),
        "MB/s": MeasurementDefinition(singular: "megabyte per second", plural: "megabytes per second"),
        "Mbps": MeasurementDefinition(singular: "megabit per second", plural: "megabits per second"),
        "mbps": MeasurementDefinition(singular: "megabit per second", plural: "megabits per second"),
        "Mb/s": MeasurementDefinition(singular: "megabit per second", plural: "megabits per second"),
        "GBps": MeasurementDefinition(singular: "gigabyte per second", plural: "gigabytes per second"),
        "GB/s": MeasurementDefinition(singular: "gigabyte per second", plural: "gigabytes per second"),
        "Gbps": MeasurementDefinition(singular: "gigabit per second", plural: "gigabits per second"),
        "gbps": MeasurementDefinition(singular: "gigabit per second", plural: "gigabits per second"),
        "Gb/s": MeasurementDefinition(singular: "gigabit per second", plural: "gigabits per second"),
        "TBps": MeasurementDefinition(singular: "terabyte per second", plural: "terabytes per second"),
        "TB/s": MeasurementDefinition(singular: "terabyte per second", plural: "terabytes per second"),
        "Tbps": MeasurementDefinition(singular: "terabit per second", plural: "terabits per second"),
        "tbps": MeasurementDefinition(singular: "terabit per second", plural: "terabits per second"),
        "Tb/s": MeasurementDefinition(singular: "terabit per second", plural: "terabits per second"),
        "MB": MeasurementDefinition(singular: "megabyte", plural: "megabytes"),
        "Mb": MeasurementDefinition(singular: "megabit", plural: "megabits"),
        "mb": MeasurementDefinition(singular: "megabit", plural: "megabits"),
        "lb": MeasurementDefinition(singular: "pound", plural: "pounds"),
        "lbs": MeasurementDefinition(singular: "pound", plural: "pounds"),
        "GB": MeasurementDefinition(singular: "gigabyte", plural: "gigabytes"),
        "Gb": MeasurementDefinition(singular: "gigabit", plural: "gigabits"),
        "gb": MeasurementDefinition(singular: "gigabit", plural: "gigabits"),
        "TB": MeasurementDefinition(singular: "terabyte", plural: "terabytes"),
        "Tb": MeasurementDefinition(singular: "terabit", plural: "terabits"),
        "tb": MeasurementDefinition(singular: "terabit", plural: "terabits"),
        "RPM": MeasurementDefinition(singular: "rotation per minute", plural: "rotations per minute"),
        "rpm": MeasurementDefinition(singular: "rotation per minute", plural: "rotations per minute"),
    ]

    private static let measurementAlternationPattern = measurementDefinitions.keys
        .sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs < rhs
            }

            return lhs.count > rhs.count
        }
        .map(NSRegularExpression.escapedPattern(for:))
        .joined(separator: "|")

    private static let spacedMeasuredValueRegex = try? NSRegularExpression(
        pattern: "(?<![#$£€[:alnum:]])([0-9][0-9,]*(?:\\.[0-9]+)?) (" + measurementAlternationPattern + ")(?![[:alnum:]])",
    )

    private static let spokenWordExpansions: [String: String] = [
        "cos": "cosine",
        "sin": "sine",
        "tan": "tangent",
        "acos": "arc cosine",
        "asin": "arc sine",
        "atan": "arc tangent",
        "f16": "float sixteen",
        "f32": "float thirty two",
        "f64": "float sixty four",
        "i8": "signed integer eight",
        "i16": "signed integer sixteen",
        "i32": "signed integer thirty two",
        "i64": "signed integer sixty four",
        "u8": "unsigned integer eight",
        "u16": "unsigned integer sixteen",
        "u32": "unsigned integer thirty two",
        "u64": "unsigned integer sixty four",
        "isize": "signed integer size",
        "usize": "unsigned integer size",
    ]

    private static let spokenNumericWidths: [String: String] = [
        "8": "eight",
        "16": "sixteen",
        "32": "thirty two",
        "64": "sixty four",
    ]

    static func spelledOut(_ text: String) -> String {
        text.map { String($0) }.joined(separator: " ")
    }

    static func spokenNumber(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: ",", with: "")
        let decimal = NSDecimalNumber(string: normalized, locale: Locale(identifier: "en_US_POSIX"))

        guard decimal != .notANumber else { return text }

        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return formatter.string(from: decimal) ?? text
    }

    static func spokenCodeBlock(
        _ body: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
        profile: SpeakSwiftlyNormalization.Profile = .base,
    ) -> String {
        let spoken = spokenEmbeddedCode(
            body,
            requestContext: requestContext,
            profile: profile,
        )
        return spoken.isEmpty ? "Code sample." : "Code sample. \(spoken). End code sample."
    }

    static func spokenInlineCode(
        _ body: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
        profile: SpeakSwiftlyNormalization.Profile = .base,
    ) -> String {
        let spoken = spokenEmbeddedCode(
            body,
            requestContext: requestContext,
            profile: profile,
        )
        return spoken.isEmpty ? " code " : " \(spoken) "
    }

    static func spokenEmbeddedCode(
        _ body: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
        profile: SpeakSwiftlyNormalization.Profile = .base,
    ) -> String {
        if isLikelyFileLineReference(body) {
            return spokenFileReference(body, style: .balanced, requestContext: requestContext)
        }

        if isLikelyURL(body) {
            return spokenURL(body)
        }

        if isLikelyEmbeddedFilePath(body) {
            return spokenPath(body, requestContext: requestContext)
        }

        return spokenCode(
            body,
            doubleColonPolicy: doubleColonSpeechPolicy(for: profile),
        )
    }

    static func spokenSource(
        _ text: String,
        format: SpeakSwiftlyNormalization.SourceFormat,
        profile: SpeakSwiftlyNormalization.Profile = .base,
    ) -> String {
        switch format {
            case .generic, .swift, .python, .rust:
                spokenCode(
                    text,
                    doubleColonPolicy: doubleColonSpeechPolicy(for: profile),
                )
        }
    }

    static func doubleColonSpeechPolicy(
        for profile: SpeakSwiftlyNormalization.Profile,
    ) -> DoubleColonSpeechPolicy {
        profile.replacement(id: "explicit-function-call") == nil ? .silent : .verbose
    }

    static func spokenCurrencyAmount(_ text: String) -> String {
        guard let parsed = parsedCurrencyAmount(in: text) else { return text }

        let wholePart = spokenNumber(parsed.wholePart)
        let majorUnit = isSingularNumber(parsed.wholePart) ? parsed.definition.singular : parsed.definition.plural

        guard let fractionalPart = parsed.fractionalPart, fractionalPart != "00" else {
            return "\(wholePart) \(majorUnit)"
        }

        let spokenFraction = spokenNumber(String(Int(fractionalPart) ?? 0))

        if let minorSingular = parsed.definition.minorSingular,
           let minorPlural = parsed.definition.minorPlural {
            let minorUnit = fractionalPart == "01" ? minorSingular : minorPlural
            return "\(wholePart) \(majorUnit)\(parsed.definition.decimalJoiner)\(spokenFraction) \(minorUnit)"
        }

        return "\(wholePart) \(majorUnit)\(parsed.definition.decimalJoiner)\(spokenFraction)"
    }

    static func spokenMeasuredValue(_ text: String) -> String {
        guard let parsed = parsedMeasuredValue(in: text) else { return text }

        let spokenValue = spokenNumber(parsed.numericPart)
        let unit = isSingularNumber(parsed.numericPart) ? parsed.definition.singular : parsed.definition.plural
        return "\(spokenValue) \(unit)"
    }

    static func normalizeSpacedMeasuredValues(_ text: String) -> String {
        guard let spacedMeasuredValueRegex else { return text }

        let matches = spacedMeasuredValueRegex.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
        )

        guard !matches.isEmpty else { return text }

        var normalized = text

        for match in matches.reversed() {
            guard let range = Range(match.range, in: normalized) else { continue }

            let candidate = String(normalized[range])
            let spoken = spokenMeasuredValue(candidate)

            guard spoken != candidate else { continue }

            normalized.replaceSubrange(range, with: spoken)
        }

        return normalized
    }

    static func spokenSegment(_ text: String) -> String {
        let broken = insertWordBreaks(in: text)
        let words = naturalLanguageWords(in: broken)
        if words.isEmpty {
            return broken
        }
        return expandSpokenWords(words).joined(separator: " ")
    }

    static func insertWordBreaks(in text: String) -> String {
        guard !text.isEmpty else { return text }

        let acronymNormalized = text.replacingOccurrences(
            of: #"([a-z])([A-Z]{2,})([A-Z][a-z])"#,
            with: "$1 $2 $3",
            options: .regularExpression,
        )

        var output = ""
        var previous: Character?
        let characters = Array(acronymNormalized)

        for character in characters {
            defer { previous = character }

            guard let previous else {
                output.append(character)
                continue
            }

            let needsBreak =
                (previous.isLowercase && character.isUppercase)
                    || (previous.isLetter && character.isNumber)
                    || (previous.isNumber && character.isLetter)

            if needsBreak, output.last != " " {
                output.append(" ")
            }

            output.append(character)
        }

        return output
    }

    private static func expandSpokenWords(_ words: [String]) -> [String] {
        var expanded: [String] = []
        var index = 0

        while index < words.count {
            let current = words[index]
            let lowercasedCurrent = current.lowercased()

            if let directExpansion = spokenWordExpansions[lowercasedCurrent] {
                expanded.append(directExpansion)
                index += 1
                continue
            }

            if index + 1 < words.count,
               let combinedTypeExpansion = spokenTypedNumericWord(
                   head: lowercasedCurrent,
                   width: words[index + 1],
               ) {
                expanded.append(combinedTypeExpansion)
                index += 2
                continue
            }

            expanded.append(current)
            index += 1
        }

        return expanded
    }

    private static func spokenTypedNumericWord(head: String, width: String) -> String? {
        guard let spokenWidth = spokenNumericWidths[width] else { return nil }

        switch head {
            case "f", "float":
                return "float \(spokenWidth)"
            case "i", "int":
                return "signed integer \(spokenWidth)"
            case "u", "uint":
                return "unsigned integer \(spokenWidth)"
            default:
                return nil
        }
    }

    private static func measurementDefinition(for suffix: String) -> MeasurementDefinition? {
        if let exact = measurementDefinitions[suffix] {
            return exact
        }

        return measurementDefinitions[suffix.lowercased()]
    }

    private static func normalizedNumberString(
        _ text: String,
        maxFractionDigits: Int? = nil,
    ) -> String? {
        let normalized = text.replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else { return nil }

        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        guard let wholePart = parts.first, !wholePart.isEmpty, wholePart.allSatisfy(\.isNumber) else {
            return nil
        }

        if parts.count == 2 {
            let fractionalPart = parts[1]
            guard !fractionalPart.isEmpty, fractionalPart.allSatisfy(\.isNumber) else {
                return nil
            }

            if let maxFractionDigits, fractionalPart.count > maxFractionDigits {
                return nil
            }
        }

        return normalized
    }

    private static func isSingularNumber(_ text: String) -> Bool {
        let decimal = NSDecimalNumber(
            string: text.replacingOccurrences(of: ",", with: ""),
            locale: Locale(identifier: "en_US_POSIX"),
        )

        return decimal != .notANumber && decimal == NSDecimalNumber.one
    }

    static func parsedCurrencyAmount(in text: String) -> ParsedCurrencyAmount? {
        guard let symbol = text.first, let definition = currencyDefinitions[symbol] else { return nil }

        let numericPortion = String(text.dropFirst())
        guard let normalized = normalizedNumberString(numericPortion, maxFractionDigits: 2) else {
            return nil
        }

        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let wholePart = parts[0]
        let fractionalPart = parts.count == 2
            ? parts[1].padding(toLength: 2, withPad: "0", startingAt: 0)
            : nil

        return ParsedCurrencyAmount(
            definition: definition,
            wholePart: wholePart,
            fractionalPart: fractionalPart,
        )
    }

    static func parsedMeasuredValue(in text: String) -> ParsedMeasuredValue? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: false).map(String.init)

        if parts.count == 2 {
            guard let numericPart = normalizedNumberString(parts[0]),
                  let definition = measurementDefinition(for: parts[1]) else {
                return nil
            }

            return ParsedMeasuredValue(
                numericPart: numericPart,
                definition: definition,
            )
        }

        guard parts.count == 1 else { return nil }

        let token = parts[0]
        guard let splitIndex = token.firstIndex(where: \.isLetter) else { return nil }

        let numericPart = String(token[..<splitIndex])
        let suffix = String(token[splitIndex...])

        guard let normalizedNumber = normalizedNumberString(numericPart),
              let definition = measurementDefinition(for: suffix) else {
            return nil
        }

        return ParsedMeasuredValue(
            numericPart: normalizedNumber,
            definition: definition,
        )
    }
}
