extension PlaybackQueue {
    func bind(_ hooks: PlaybackHooks) {
        self.hooks = hooks
        Task {
            await driver.bindEnvironmentEvents { [weak self] (event: PlaybackEnvironmentEvent) in
                guard let self else { return }

                let activeRequest = await activeRequestSummary()
                await hooks.handleEnvironmentEvent(event, activeRequest)
            }
        }
    }

    func prepare(sampleRate: Double) async throws -> Bool {
        try await driver.prepare(sampleRate: sampleRate)
    }

    func handle(_ action: PlaybackAction) async -> PlaybackState {
        switch action {
            case .pause:
                let driverState = await driver.pause()
                return resolvedPlaybackState(driverState: driverState)
            case .resume:
                let driverState = await driver.resume()
                return resolvedPlaybackState(driverState: driverState)
            case .state:
                let driverState = await driver.state()
                return resolvedPlaybackState(driverState: driverState)
        }
    }
}
