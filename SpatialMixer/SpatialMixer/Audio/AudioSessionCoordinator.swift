//
//  AudioSessionCoordinator.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 21-02-26.
//

import Foundation
import AVFoundation
import Combine
import os

private let logger = Logger(subsystem: "com.jqnchvz.SpatialMixer", category: "AudioSessionCoordinator")

/// Owns all audio infrastructure and coordinates tap lifecycle.
///
/// Lives as a single `@StateObject` in `SpatialMixerApp`, shared between the
/// `MenuBarExtra` and the settings `Window` via `@EnvironmentObject`.
/// This ensures both scenes always see the same engine state.
@MainActor
class AudioSessionCoordinator: ObservableObject {

    // MARK: - Owned objects (injected into scenes as environment objects)

    let permissions      = AudioPermissions()
    let processDiscovery = ProcessDiscovery()
    let captureManager   = AudioCaptureManager()
    let spatialEngine    = SpatialAudioEngine()

    // MARK: - Published state

    @Published private(set) var activeTapProcesses: Set<pid_t> = []
    @Published var engineError: String?

    // MARK: - Private

    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    init() {
        // When the audio device changes, AVAudioEngine wipes all nodes and fires
        // resetGeneration. Clear captured UI state to match.
        spatialEngine.$resetGeneration
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                activeTapProcesses.removeAll()
                captureManager.removeAllTaps()
            }
            .store(in: &cancellables)
    }

    // MARK: - Tap Management

    func startTap(for app: AppInfo) {
        logger.info("🔵 startTap for \(app.name) (PID: \(app.processID))")

        do {
            if spatialEngine.engineStatus != .running {
                try spatialEngine.start()
                engineError = nil
            }

            let tap = try captureManager.createTap(for: app.processID)

            guard let format = tap.audioFormat else {
                throw AudioTapError.formatNotAvailable
            }

            try spatialEngine.addSource(for: app.processID, format: format)

            let appName    = app.name
            let processID  = app.processID
            let firstBufferLogged = OSAllocatedUnfairLock(initialState: false)

            tap.bufferHandler = { [weak spatialEngine = spatialEngine] buffer in
                spatialEngine?.scheduleBuffer(buffer, for: processID)

                let isFirst = firstBufferLogged.withLock { (logged: inout Bool) -> Bool in
                    guard !logged else { return false }
                    logged = true
                    return true
                }
                guard isFirst else { return }
                logger.info("✅ First buffer for \(appName) — \(buffer.format.sampleRate)Hz \(buffer.format.channelCount)ch")
            }

            activeTapProcesses.insert(app.processID)
            logger.info("✓ Started tap for \(app.name)")

        } catch {
            captureManager.removeTap(for: app.processID)
            if activeTapProcesses.isEmpty { spatialEngine.stop() }
            engineError = error.localizedDescription
            logger.error("✗ Failed to start tap for \(app.name): \(error.localizedDescription)")
        }
    }

    func stopTap(for processID: pid_t) {
        spatialEngine.removeSource(for: processID)
        captureManager.removeTap(for: processID)
        activeTapProcesses.remove(processID)
        logger.info("✓ Stopped tap for PID \(processID)")

        if activeTapProcesses.isEmpty {
            spatialEngine.stop()
            engineError = nil
        }
    }
}
