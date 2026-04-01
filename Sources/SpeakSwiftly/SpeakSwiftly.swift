import Foundation

// MARK: - Entry Point

@main
enum SpeakSwiftly {
    static func main() async {
        let runtime = WorkerRuntime.live()
        await runtime.start()

        while let line = readLine() {
            await runtime.accept(line: line)
        }

        await runtime.shutdown()
    }
}
