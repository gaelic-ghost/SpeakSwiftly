import Foundation
import SpeakSwiftlyCore

// MARK: - Entry Point

@main
enum SpeakSwiftlyCLI {
    static func main() async {
        let runtime = await SpeakSwiftly.live()
        await runtime.start()

        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                await runtime.accept(line: line)
            }
        } catch {
            fputs("SpeakSwiftly stopped reading stdin because the standard input stream failed unexpectedly. \(error.localizedDescription)\n", stderr)
        }

        await runtime.shutdown()
    }
}
