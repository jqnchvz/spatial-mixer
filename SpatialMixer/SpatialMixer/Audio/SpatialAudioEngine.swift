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

    // MARK: - Audio Engine Components

    private let engine = AVAudioEngine()
    private let environmentNode = AVAudioEnvironmentNode()

    /// Standard engine format: 48kHz stereo Float32 non-interleaved
    /// This matches most modern audio sources and provides optimal quality
    private let engineFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000,
        channels: 2,
        interleaved: false
    )!

    // MARK: - Source Management

    /// Maps process IDs to their audio source nodes
    private var audioSources: [pid_t: AudioSourceNode] = [:]

    /// Configuration change observer
    private var configChangeObserver: NSObjectProtocol?

    // MARK: - Initialization

    init() {
        setupEngine()
        observeConfigurationChanges()
    }

    deinit {
        // Note: deinit is nonisolated, but we can safely access engine
        // since the object is being deallocated
        if engine.isRunning {
            engine.stop()
        }
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Engine Lifecycle

    /// Set up the audio engine graph: PlayerNodes → Mixer → Environment → Output
    private func setupEngine() {
        // Attach environment node to engine
        engine.attach(environmentNode)

        // Connect environment node to main mixer
        // Environment node handles 3D spatial positioning with HRTF
        engine.connect(
            environmentNode,
            to: engine.mainMixerNode,
            format: engineFormat
        )

        // Configure environment node for optimal spatial audio
        environmentNode.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environmentNode.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: 0,
            pitch: 0,
            roll: 0
        )

        // Use high-quality HRTF rendering for best spatial accuracy
        // HRTF (Head-Related Transfer Function) simulates how ears perceive 3D sound
        environmentNode.renderingAlgorithm = .HRTFHQ

        print("🎵 Audio engine configured with spatial processing")
    }

    /// Start the audio engine
    func start() throws {
        guard engineStatus != .running else {
            print("⚠️ Engine already running")
            return
        }

        engineStatus = .starting

        do {
            // Prepare engine for rendering
            engine.prepare()

            // Start the engine - this begins audio processing
            try engine.start()

            engineStatus = .running
            print("✅ Audio engine started successfully")

        } catch {
            engineStatus = .error(error.localizedDescription)
            throw SpatialAudioEngineError.engineStartFailed(underlying: error)
        }
    }

    /// Stop the audio engine and all sources
    func stop() {
        guard engineStatus == .running else { return }

        // Stop all player nodes first
        for source in audioSources.values {
            source.playerNode.stop()
        }

        // Stop the engine
        engine.stop()

        engineStatus = .stopped
        print("🛑 Audio engine stopped")
    }

    // MARK: - Source Management

    /// Add a new audio source for the specified process
    /// - Parameters:
    ///   - processID: Process ID of the app
    ///   - format: Audio format from the Core Audio Tap
    /// - Throws: SpatialAudioEngineError if source creation fails
    func addSource(for processID: pid_t, format: AVAudioFormat) throws {
        // Check for duplicate
        guard audioSources[processID] == nil else {
            throw SpatialAudioEngineError.sourceAlreadyExists(processID: processID)
        }

        print("🔧 Adding audio source for process \(processID)")
        print("   Tap format: \(format.sampleRate)Hz, \(format.channelCount)ch")

        // Create player node for this source
        let playerNode = AVAudioPlayerNode()

        // Attach player node to engine
        engine.attach(playerNode)

        // Create format converter if needed
        var converter: AVAudioConverter?
        var connectionFormat = format

        // Check if format conversion is needed
        if !isFormatCompatible(format) {
            print("   ⚡ Format mismatch - creating converter")
            print("      From: \(format.sampleRate)Hz \(format.channelCount)ch")
            print("      To: \(engineFormat.sampleRate)Hz \(engineFormat.channelCount)ch")

            guard let conv = AVAudioConverter(from: format, to: engineFormat) else {
                throw SpatialAudioEngineError.formatConversionFailed(
                    from: formatDescription(format),
                    to: formatDescription(engineFormat)
                )
            }

            converter = conv
            connectionFormat = engineFormat
        }

        // Connect: PlayerNode → EnvironmentNode
        // This enables 3D spatial positioning for this source
        engine.connect(
            playerNode,
            to: environmentNode,
            format: connectionFormat
        )

        // Create source node wrapper
        let sourceNode = AudioSourceNode(
            processID: processID,
            playerNode: playerNode,
            format: format,
            converter: converter
        )

        // Configure default spatial positioning
        // Use ambienceBed mode to preserve stereo information
        playerNode.sourceMode = .ambienceBed

        // Default position: front-center
        playerNode.position = AVAudio3DPoint(x: 0, y: 0, z: -1)

        // Store source
        audioSources[processID] = sourceNode
        activeSourceCount = audioSources.count

        // Start the player node if engine is running
        if engineStatus == .running && !playerNode.isPlaying {
            playerNode.play()
        }

        print("✅ Audio source added for process \(processID)")
    }

    /// Remove an audio source
    /// - Parameter processID: Process ID of the app
    func removeSource(for processID: pid_t) {
        guard let sourceNode = audioSources.removeValue(forKey: processID) else {
            print("⚠️ Attempted to remove non-existent source: \(processID)")
            return
        }

        // Stop the player node
        sourceNode.playerNode.stop()

        // Detach from engine
        engine.detach(sourceNode.playerNode)

        activeSourceCount = audioSources.count

        print("🗑️ Removed audio source for process \(processID)")
    }

    // MARK: - Buffer Scheduling

    /// Schedule an audio buffer for playback
    /// This method is THREAD-SAFE and can be called from Core Audio's IOProc queue
    /// - Parameters:
    ///   - buffer: The audio buffer to schedule
    ///   - processID: Process ID of the source app
    func scheduleBuffer(_ buffer: AVAudioPCMBuffer, for processID: pid_t) {
        // Thread-safe access: audioSources dictionary is only modified on main thread
        // This read operation is safe from any thread
        guard let sourceNode = audioSources[processID] else {
            // Source may have been removed - this is normal
            return
        }

        // Check buffer queue depth to prevent memory buildup
        // If consumer is slow, drop frames to maintain real-time behavior
        let pending = sourceNode.scheduledBufferCount - sourceNode.renderedBufferCount
        guard pending < 5 else {
            // Queue is full - drop this buffer to prevent latency buildup
            if pending == 5 {
                print("⚠️ Buffer queue full for process \(processID) - dropping frames")
            }
            return
        }

        // Convert format if needed
        let bufferToSchedule: AVAudioPCMBuffer
        if let converter = sourceNode.converter {
            // Format conversion required
            guard let convertedBuffer = convertBuffer(buffer, using: converter) else {
                print("❌ Buffer conversion failed for process \(processID)")
                return
            }
            bufferToSchedule = convertedBuffer
        } else {
            // No conversion needed - use original buffer
            bufferToSchedule = buffer
        }

        // Schedule buffer for playback
        // AVAudioPlayerNode.scheduleBuffer is thread-safe and can be called from any thread
        // The completion handler tracks when the buffer has been rendered
        sourceNode.playerNode.scheduleBuffer(
            bufferToSchedule,
            completionCallbackType: .dataRendered
        ) { [weak self] _ in
            // This runs on an internal AVAudioEngine thread
            // Update counters to track queue depth
            self?.handleBufferCompleted(for: processID)
        }

        // Update scheduled count (atomic increment is safe)
        sourceNode.scheduledBufferCount += 1

        // Update @Published state on main thread only when needed
        if sourceNode.scheduledBufferCount == 1 {
            Task { @MainActor in
                // First buffer scheduled - could update UI if needed
            }
        }
    }

    /// Handle buffer completion callback
    /// - Parameter processID: Process ID of the source
    private nonisolated func handleBufferCompleted(for processID: pid_t) {
        // This is called from AVAudioEngine's internal thread
        // Access to AudioSourceNode is thread-safe since counters are value types
        // and dictionary is only modified on main thread
        Task { @MainActor in
            self.audioSources[processID]?.renderedBufferCount += 1
        }
    }

    // MARK: - Format Utilities

    /// Check if a format is compatible with the engine format
    private func isFormatCompatible(_ format: AVAudioFormat) -> Bool {
        return format.sampleRate == engineFormat.sampleRate &&
               format.channelCount == engineFormat.channelCount &&
               format.commonFormat == engineFormat.commonFormat
    }

    /// Create a human-readable format description
    private func formatDescription(_ format: AVAudioFormat) -> String {
        return "\(format.sampleRate)Hz \(format.channelCount)ch \(format.commonFormat.rawValue)"
    }

    /// Convert an audio buffer using the provided converter
    private func convertBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter
    ) -> AVAudioPCMBuffer? {
        // Calculate output buffer capacity
        // Conversion ratio = outputSampleRate / inputSampleRate
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: outputCapacity
        ) else {
            return nil
        }

        var error: NSError?
        // Capture inputBuffer in a local to satisfy Sendable requirements
        let capturedBuffer = inputBuffer
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return capturedBuffer
        }

        guard status != .error, error == nil else {
            print("❌ Format conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }

        return outputBuffer
    }

    // MARK: - Configuration Changes

    /// Observe audio configuration changes (device disconnection, sample rate changes)
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

    /// Handle audio configuration changes by restarting the engine
    private func handleConfigurationChange() {
        print("🔄 Audio configuration changed - restarting engine")

        // Stop current playback
        stop()

        // Attempt to restart
        do {
            try start()
            print("✅ Engine restarted successfully")
        } catch {
            engineStatus = .error("Failed to restart after configuration change")
            print("❌ Failed to restart engine: \(error.localizedDescription)")
        }
    }
}

// MARK: - Audio Source Node

/// Wrapper for an individual audio source with its associated nodes and state
private class AudioSourceNode {
    let processID: pid_t
    let playerNode: AVAudioPlayerNode
    let format: AVAudioFormat
    let converter: AVAudioConverter?

    /// Atomic counters for tracking buffer queue depth
    var scheduledBufferCount: Int = 0
    var renderedBufferCount: Int = 0

    init(
        processID: pid_t,
        playerNode: AVAudioPlayerNode,
        format: AVAudioFormat,
        converter: AVAudioConverter?
    ) {
        self.processID = processID
        self.playerNode = playerNode
        self.format = format
        self.converter = converter
    }
}
