import Markdown
import SwiftSoup

extension TextNormalizer {
    static func markdownDocument(from text: String) -> Markdown.Document {
        Markdown.Document(parsing: text)
    }

    static func htmlDocument(from text: String) throws -> SwiftSoup.Document {
        try SwiftSoup.parse(text)
    }

    static func markdownHasStructure(_ text: String) -> Bool {
        markdownDocument(from: text).hasMeaningfulMarkdownStructure
    }

    static func htmlHasStructure(_ text: String) -> Bool {
        (try? htmlDocument(from: text).hasMeaningfulHTMLStructure) ?? false
    }
}

private extension Markup {
    var hasMeaningfulMarkdownStructure: Bool {
        children.contains { child in
            switch child {
                case is Heading,
                     is Link,
                     is InlineCode,
                     is CodeBlock:
                    true
                default:
                    child.hasMeaningfulMarkdownStructure
            }
        }
    }
}

private extension SwiftSoup.Document {
    var hasMeaningfulHTMLStructure: Bool {
        guard let body = body() else { return false }

        return body.children().contains { element in
            element.tagName().lowercased() != "body"
        }
    }
}
