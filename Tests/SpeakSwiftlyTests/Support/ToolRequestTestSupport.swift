@testable import SpeakSwiftly
@testable import SpeakSwiftlyTool

extension SpeakSwiftly.Runtime {
    func accept(line: String) async {
        do {
            let request = try ToolRequest.decode(from: line)
            await request.submit(to: self)
        } catch {
            await tool.reject(line: line, error: error)
        }
    }
}
