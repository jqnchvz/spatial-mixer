//
//  SpatialAudioEngine.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 15-02-26.
//

import Foundation
@preconcurrency import AVFoundation
import Combine

/// Engine status states
enum EngineStatus: Equatable {
    case stopped
    case starting
    case running
    case error(String)

    static func == (lhs: EngineStatus, rhs: EngineStatus) -> Bool {
        switch (lhs, rhs) {
        case (.stopped, .stopped), (.starting, .starting), (.running, .running):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// Manages the AVAudioEngine pipeline with spatial audio processing
@MainActor
class SpatialAudioEngine: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var engineStatus: EngineStatus = .stopped
    @Published private(set) var activeSourceCount: Int = 0
    /// Incremented each time a device change forces a full engine reset.
    /// MenuBarView observes this to clear its captured-source state.
    @Published private(set) var resetGeneration: Int = 0

    // MARK: - Audio Engine Components

    private let engine = AVAudioEngine()
    private let environmentNode = AVAudioEnvironmentNode()

    /// Standard engine format: 48kHz stereo Float32 non-interleaved
    private let engineFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000,
        channels: 2,
        interleaved: false
    )!

    // MARK: - Source Management

    /// Main-actor dictionary — only written from @MainActor context.
    private var audioSources: [pid_t: AudioSourceNode] = [:]

    /// Shadow dictionary for IOProc-queue reads in scheduleBuffer.
    /// Written from @MainActor (add/remove source), read from IOProc queue.
    /// The read/write windows don't overlap in practice (sources change rarely
    /// compared to the continuous buffer scheduling rate).
    nonisolated(unsafe) private var sourceNodesForScheduling: [pid_t: AudioSourceNode] = [:]

    /// Configuration change observer
    private var configChangeObserver: NSObjectProtocol?

    // MARK: - Initialization

    init() {
        setupEngine()
        observeConfigurationChanges()
    }

    deinit {
        if engine.isRunning {
            engine.stop()
        }
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Engine Lifecycle

    /// Connect the static part of the graph: EnvironmentNode → MainMixer.
    /// Must be called after any AVAudioEngineConfigurationChange wipes the graph.
    private func setupEngine() {
        engine.attach(environmentNode)
        engine.connect(environmentNode, to: engine.mainMixerNode, format: engineFormat)

        environmentNode.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environmentNode.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: 0, pitch: 0, roll: 0
        )
        // HRTF (Head-Related Transfer Function) — realistic 3D spatial rendering
        environmentNode.renderingAlgorithm = .HRTFHQ

        print("🎵 Audio engine graph configured")
    }

    /// Start the audio engine
    func start() throws {
        guard engineStatus != .running else { return }

        engineStatus = .starting
        do {
            engine.prepare()
            try engine.start()
            engineStatus = .running
            print("✅ Audio engine started")
        } catch {
            engineStatus = .error(error.localizedDescription)
            throw SpatialAudioEngineError.engineStartFailed(underlying: error)
        }
    }

    /// Stop the audio engine and all sources
    func stop() {
        guard engineStatus == .running else { return }

        for source in audioSources.values {
            source.playerNode.stop()
        }
        engine.stop()
        engineStatus = .stopped
        print("🛑 Audio engine stopped")
    }

    // MARK: - Source Management

    func addSource(for processID: pid_t, format: AVAudioFormat) throws {
        guard audioSources[processID] == nil else {
            throw SpatialAudioEngineError.sourceAlreadyExists(processID: processID)
        }

        print("🔧 Adding source for PID \(processID) — \(format.sampleRate)Hz \(format.channelCount)ch")

        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)

        var converter: AVAudioConverter?
        var connectionFormat = format

        if !isFormatCompatible(format) {
            print("   ⚡ Format mismatch — creating converter to \(engineFormat.sampleRate)Hz")
            guard let conv = AVAudioConverter(from: format, to: engineFormat) else {
                throw SpatialAudioEngineError.formatConversionFailed(
                    from: formatDescription(format),
                    to: formatDescription(engineFormat)
                )
            }
            converter = conv
            connectionFormat = engineFormat
        }

        engine.connect(playerNode, to: environmentNode, format: connectionFormat)

        let sourceNode = AudioSourceNode(
            processID: processID,
            playerNode: playerNode,
            format: format,
            converter: converter
        )

        playerNode.sourceMode = .ambienceBed
        playerNode.position = AVAudio3DPoint(x: 0, y: 0, z: -1)

        // Update both dictionaries together while on main actor
        audioSources[processID] = sourceNode
        sourceNodesForScheduling[processID] = sourceNode
        activeSourceCount = audioSources.count

        if engineStatus == .running && !playerNode.isPlaying {
            playerNode.play()
        }

        print("✅ Source added for PID \(processID)")
    }

    func removeSource(for processID: pid_t) {
        guard let sourceNode = audioSources.removeValue(forKey: processID) else {
            return
        }
        // Remove from scheduling dictionary before stopping the node so that
        // any in-flight IOProc calls drop cleanly.
        sourceNodesForScheduling.removeValue(forKey: processID)

        sourceNode.playerNode.stop()
        engine.detach(sourceNode.playerNode)
        activeSourceCount = audioSources.count

        print("🗑️ Removed source for PID \(processID)")
    }

    // MARK: - Buffer Scheduling (nonisolated — called from IOProc queue)

    /// Schedule an audio buffer for playback.
    /// Marked nonisolated so calls from the Core Audio IOProc queue do NOT
    /// hop to the main thread. Uses `sourceNodesForScheduling` (a shadow copy
    /// of `audioSources`) which is safe to read without actor isolation.
    nonisolated func scheduleBuffer(_ buffer: AVAudioPCMBuffer, for processID: pid_t) {
        guard let sourceNode = sourceNodesForScheduling[processID] else { return }

        // Backpressure: drop frames if the consumer (AVAudioEngine render thread) is slow
        let pending = sourceNode.scheduledBufferCount - sourceNode.renderedBufferCount
        guard pending < 5 else { return }

        let bufferToSchedule: AVAudioPCMBuffer
        if let converter = sourceNode.converter {
            guard let converted = convertBuffer(buffer, using: converter) else { return }
            bufferToSchedule = converted
        } else {
            bufferToSchedule = buffer
        }

        sourceNode.playerNode.scheduleBuffer(
            bufferToSchedule,
            completionCallbackType: .dataRendered
        ) { [weak self] _ in
            self?.handleBufferCompleted(for: processID)
        }

        sourceNode.scheduledBufferCount += 1
    }

    private nonisolated func handleBufferCompleted(for processID: pid_t) {
        // Increment rendered counter without hopping to main actor
        sourceNodesForScheduling[processID]?.renderedBufferCount += 1
    }

    // MARK: - Format Utilities

    private func isFormatCompatible(_ format: AVAudioFormat) -> Bool {
        return format.sampleRate == engineFormat.sampleRate
            && format.channelCount == engineFormat.channelCount
            && format.commonFormat == engineFormat.commonFormat
    }

    private func formatDescription(_ format: AVAudioFormat) -> String {
        "\(format.sampleRate)Hz \(format.channelCount)ch"
    }

    private nonisolated func convertBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter
    ) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: outputCapacity
        ) else { return nil }

        var error: NSError?
        let capturedBuffer = inputBuffer
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return capturedBuffer
        }

        guard status != .error, error == nil else { return nil }
        return outputBuffer
    }

    // MARK: - Configuration Changes

    private func observeConfigurationChanges() {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleConfigurationChange()
            }
        }
    }

    /// Called when the audio hardware changes (headphones connected/disconnected, etc.)
    ///
    /// AVAudioEngine automatically stops itself and WIPES all node connections
    /// on a configuration change. We must rebuild the entire graph before restarting.
    private func handleConfigurationChange() {
        print("🔄 Audio configuration changed — rebuilding engine graph")

        // Engine was auto-stopped by AVAudioEngine; update our tracked status.
        engineStatus = .stopped

        // Stop and detach all source player nodes (their connections were wiped).
        for sourceNode in audioSources.values {
            sourceNode.playerNode.stop()
            engine.detach(sourceNode.playerNode)
        }

        // Clear all sources. MenuBarView observes resetGeneration to clean up its UI.
        audioSources.removeAll()
        sourceNodesForScheduling.removeAll()
        activeSourceCount = 0
        resetGeneration += 1

        // Rebuild the static graph (EnvironmentNode → MainMixer).
        setupEngine()

        // Restart the engine on the new device.
        do {
            try start()
            print("✅ Engine restarted on new audio device")
        } catch {
            engineStatus = .error("Restart failed: \(error.localizedDescription)")
            print("❌ Engine restart failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Audio Source Node

private class AudioSourceNode {
    let processID: pid_t
    let playerNode: AVAudioPlayerNode
    let format: AVAudioFormat
    let converter: AVAudioConverter?

    var scheduledBufferCount: Int = 0
    var renderedBufferCount: Int = 0

    init(processID: pid_t, playerNode: AVAudioPlayerNode, format: AVAudioFormat, converter: AVAudioConverter?) {
        self.processID = processID
        self.playerNode = playerNode
        self.format = format
        self.converter = converter
    }
}
