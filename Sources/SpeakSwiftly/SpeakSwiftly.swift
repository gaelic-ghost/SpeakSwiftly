import Foundation

// MARK: - Entry Point

@main
enum SpeakSwiftly {
    static func main() {
        let message = """
        SpeakSwiftly is the bootstrap worker scaffold for the future stdin/stdout JSONL protocol.
        This build intentionally stays minimal while the long-lived MLX worker loop is implemented.
        """

        FileHandle.standardError.write(Data(message.utf8))
        FileHandle.standardError.write(Data("\n".utf8))
    }
}
