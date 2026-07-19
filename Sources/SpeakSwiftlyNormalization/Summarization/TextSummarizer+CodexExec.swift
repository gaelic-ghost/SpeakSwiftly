import Foundation

#if os(macOS)
import Darwin
#endif

extension TextSummarizer {
    static func summarizeWithCodexExec(
        prompt: String,
        executableURL: URL? = nil,
        timeoutSeconds: TimeInterval = SummaryProviderLimits.codexExecTimeoutSeconds,
    ) async throws -> String {
#if os(macOS)
        let runner = CodexExecProcessRunner(
            prompt: prompt,
            executableURL: executableURL,
            timeoutSeconds: timeoutSeconds,
        )
        return try await withTaskCancellationHandler {
            try await runner.run()
        } onCancel: {
            runner.cancel()
        }
#else
        throw SpeakSwiftlyNormalization.SummaryError.providerUnavailable(
            "SpeakSwiftly normalization could not summarize with codex exec because Process-based CLI execution is only supported by this package on macOS.",
        )
#endif
    }
}

#if os(macOS)
private final class CodexExecProcessRunner: @unchecked Sendable {
    private enum Completion {
        case exit(Int32)
        case failure(SpeakSwiftlyNormalization.SummaryError)
    }

    private let prompt: String
    private let executableURL: URL?
    private let timeoutSeconds: TimeInterval
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let outputBuffer = BoundedOutputBuffer(limit: SummaryProviderLimits.maxOutputBytes)
    private let errorBuffer = BoundedOutputBuffer(limit: SummaryProviderLimits.maxErrorBytes)
    private let readerGroup = DispatchGroup()
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var didComplete = false

    private var completedProcessStatus: Completion?

    init(
        prompt: String,
        executableURL: URL?,
        timeoutSeconds: TimeInterval,
    ) {
        self.prompt = prompt
        self.executableURL = executableURL
        self.timeoutSeconds = timeoutSeconds
    }

    private static func timeoutDescription(_ timeoutSeconds: TimeInterval) -> String {
        if timeoutSeconds.rounded() == timeoutSeconds {
            "\(Int(timeoutSeconds))-second"
        } else {
            "\(timeoutSeconds)-second"
        }
    }

    func run() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            start(continuation: continuation)
        }
    }

    func cancel() {
        complete(
            .failure(
                SpeakSwiftlyNormalization.SummaryError.providerFailed(
                    "SpeakSwiftly normalization cancelled codex exec summarization and terminated the child process before it could return a summary.",
                ),
            ),
        )
    }

    private func start(continuation: CheckedContinuation<String, any Error>) {
        if let executableURL {
            process.executableURL = executableURL
            process.arguments = [
                "exec",
                "--ephemeral",
                "--sandbox",
                "read-only",
                "-",
            ]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "codex",
                "exec",
                "--ephemeral",
                "--sandbox",
                "read-only",
                "-",
            ]
        }
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        startPipeReader(
            handle: outputPipe.fileHandleForReading,
            buffer: outputBuffer,
        )
        startPipeReader(
            handle: errorPipe.fileHandleForReading,
            buffer: errorBuffer,
        )

        process.terminationHandler = { [weak self] process in
            self?.complete(.exit(process.terminationStatus))
        }

        configureTimeout()

        do {
            try process.run()
        } catch {
            complete(
                .failure(
                    SpeakSwiftlyNormalization.SummaryError.providerUnavailable(
                        "SpeakSwiftly normalization could not start codex exec for summarization. Confirm the Codex CLI is installed and available on PATH. \(error.localizedDescription)",
                    ),
                ),
            )
            waitForCompletion(continuation: continuation)
            return
        }

        if lock.withLock({ didComplete }) {
            terminateProcessIfNeeded()
            waitForCompletion(continuation: continuation)
            return
        }

        inputPipe.fileHandleForWriting.write(Data(prompt.utf8))
        try? inputPipe.fileHandleForWriting.close()

        waitForCompletion(continuation: continuation)
    }

    private func configureTimeout() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + timeoutSeconds)
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }

            complete(
                .failure(
                    SpeakSwiftlyNormalization.SummaryError.providerFailed(
                        "SpeakSwiftly normalization could not summarize with codex exec because the CLI exceeded the \(Self.timeoutDescription(timeoutSeconds)) timeout. SpeakSwiftly normalization terminated the child process so the host request would not hang.",
                    ),
                ),
            )
        }
        self.timer = timer
        timer.resume()
    }

    private func waitForCompletion(continuation: CheckedContinuation<String, any Error>) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                continuation.resume(
                    throwing: SpeakSwiftlyNormalization.SummaryError.providerFailed(
                        "SpeakSwiftly normalization could not summarize with codex exec because the process runner was released before the CLI returned.",
                    ),
                )
                return
            }

            let result = waitForResult()
            switch result {
                case let .success(summary):
                    continuation.resume(returning: summary)
                case let .failure(error):
                    continuation.resume(throwing: error)
            }
        }
    }

    private func waitForResult() -> Result<String, SpeakSwiftlyNormalization.SummaryError> {
        while true {
            let isComplete = lock.withLock {
                didComplete
            }

            if isComplete {
                waitForPipeReaders()
                return makeCompletionResult()
            }

            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private func makeCompletionResult() -> Result<String, SpeakSwiftlyNormalization.SummaryError> {
        let processStatus = lock.withLock {
            completedProcessStatus
        }
        let output = outputBuffer.output()
        let error = errorBuffer.output()
        cleanupHandles()

        if output.didExceedLimit {
            return .failure(
                SpeakSwiftlyNormalization.SummaryError.providerFailed(
                    "SpeakSwiftly normalization could not summarize with codex exec because the CLI returned more than \(SummaryProviderLimits.maxOutputBytes) bytes on stdout. SpeakSwiftly normalization stopped collecting output so the host process would not grow memory without bound.",
                ),
            )
        }

        if error.didExceedLimit {
            return .failure(
                SpeakSwiftlyNormalization.SummaryError.providerFailed(
                    "SpeakSwiftly normalization could not summarize with codex exec because the CLI returned more than \(SummaryProviderLimits.maxErrorBytes) bytes on stderr. SpeakSwiftly normalization stopped collecting error output so the host process would not grow memory without bound.",
                ),
            )
        }

        switch processStatus {
            case let .exit(status) where status == 0:
                return .success(output.text.trimmingCharacters(in: .whitespacesAndNewlines))
            case let .exit(status):
                return .failure(
                    SpeakSwiftlyNormalization.SummaryError.providerFailed(
                        "SpeakSwiftly normalization could not summarize with codex exec because the CLI exited with status \(status). \(error.text)",
                    ),
                )
            case let .failure(error):
                return .failure(error)
            case nil:
                return .failure(
                    SpeakSwiftlyNormalization.SummaryError.providerFailed(
                        "SpeakSwiftly normalization could not summarize with codex exec because the process completed without recording an exit status.",
                    ),
                )
        }
    }

    private func startPipeReader(
        handle: FileHandle,
        buffer: BoundedOutputBuffer,
    ) {
        readerGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            while true {
                let data = handle.readData(ofLength: 8 * 1024)
                guard !data.isEmpty else {
                    break
                }

                buffer.append(data)
            }
            self.readerGroup.leave()
        }
    }

    private func waitForPipeReaders() {
        if readerGroup.wait(timeout: .now() + 1) == .timedOut {
            cleanupHandles()
        }
    }

    private func complete(_ completion: Completion) {
        lock.withLock {
            guard !didComplete else {
                return
            }

            didComplete = true
            completedProcessStatus = completion
            timer?.cancel()
            timer = nil
            terminateProcessIfNeeded()
        }
    }

    private func terminateProcessIfNeeded() {
        guard process.isRunning else {
            return
        }

        let processID = process.processIdentifier
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [process] in
            if process.isRunning {
                kill(processID, SIGKILL)
            }
        }
    }

    private func cleanupHandles() {
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()
    }
}
#endif
