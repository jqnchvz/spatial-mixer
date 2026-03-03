//
//  SpatialAudioEngine.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 15-02-26.
//

import Foundation
@preconcurrency import AVFoundation
@preconcurrency import PHASE
import ModelIO
import Combine
import CoreMotion
import os

private let logger = Logger(subsystem: "com.jqnchvz.SpatialMixer", category: "SpatialAudioEngine")

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

/// Manages the PHASE spatial audio pipeline.
///
/// Architecture:
/// ```
/// Core Audio Tap → IOProc → AVAudioPCMBuffer
///    ↓ (AVAudioConverter for format mismatches)
/// PHASEPushStreamNode (per source)
///    → PHASESpatialPipeline (direct path + early reflections + late reverb)
///    → PHASEListener (at origin, rotated by head tracking)
/// PHASEEngine → output
/// ```
///
/// The 5×4×5 m concrete room geometry enables image-source early reflections,
/// which are the primary cue making head movement feel gradual rather than snapping.
@MainActor
class SpatialAudioEngine: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var engineStatus: EngineStatus = .stopped
    @Published private(set) var activeSourceCount: Int = 0
    /// Incremented each time a device change forces a full engine reset.
    /// MenuBarView observes this to clear its captured-source state.
    @Published private(set) var resetGeneration: Int = 0
    /// Current position preset for each source, keyed by process ID.
    @Published private(set) var sourcePresets: [pid_t: SpatialPosition] = [:]
    /// Current source mode for each source, keyed by process ID.
    /// Stored for UI display; PHASE pipeline is stereo for all sources in this version.
    /// TODO(SPAT-40): implement mode-specific pipelines (pointSource = mono, ambienceBed = stereo)
    @Published private(set) var sourceModes: [pid_t: AVAudio3DMixingSourceMode] = [:]
    /// Distance multiplier for each source (0.5 = subtle, 5.0 = very pronounced).
    @Published private(set) var sourceDistances: [pid_t: Float] = [:]
    /// Whether AirPods head tracking is currently streaming orientation updates.
    @Published private(set) var isHeadTrackingActive = false

    // MARK: - PHASE Engine Components

    private let phaseEngine = PHASEEngine(updateMode: .automatic)
    private var phaseListener: PHASEListener!

    /// Standard engine format: 48 kHz stereo Float32 non-interleaved
    private let engineFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000,
        channels: 2,
        interleaved: false
    )!

    // MARK: - Source Management

    /// Thread-safe dictionary of PHASE audio sources.
    /// Written from @MainActor (add/remove source) and read from the IOProc-adjacent
    /// callback thread (scheduleBuffer / handleBufferCompleted).
    /// OSAllocatedUnfairLock is Sendable, so nonisolated methods can access it directly.
    private let sourcesLock = OSAllocatedUnfairLock<[pid_t: PHASESourceNode]>(initialState: [:])

    /// Streams AirPods orientation for listener head tracking.
    private let headphoneMotionManager = CMHeadphoneMotionManager()

    // MARK: - Initialization

    init() {
        setupEngine()
    }

    deinit {
        phaseEngine.stop()
    }

    // MARK: - Engine Lifecycle

    private func setupEngine() {
        phaseListener = PHASEListener(engine: phaseEngine)
        phaseListener.transform = matrix_identity_float4x4
        do {
            try phaseEngine.rootObject.addChild(phaseListener)
        } catch {
            logger.error("❌ Failed to attach listener to scene: \(error.localizedDescription)")
            engineStatus = .error("Listener setup failed")
            return
        }

        setupRoomGeometry()
        logger.info("🎵 PHASE engine configured with early-reflections room")
    }

    /// Creates a fixed 5×4×5 m concrete box centred on the listener.
    /// PHASE uses this geometry for image-source early reflection simulation.
    /// PHASEShape(engine:mesh:materials:) bakes the acoustic material in at construction time.
    private func setupRoomGeometry() {
        let allocator = MDLMeshBufferDataAllocator()
        let mesh = MDLMesh(
            boxWithExtent: simd_float3(5, 4, 5),
            segments: simd_uint3(1, 1, 1),
            inwardNormals: true,        // normals face inward so inner faces are reflective
            geometryType: .triangles,
            allocator: allocator
        )

        let material = PHASEMaterial(engine: phaseEngine, preset: .concrete)
        let shape = PHASEShape(engine: phaseEngine, mesh: mesh, materials: [material])
        let occluder = PHASEOccluder(engine: phaseEngine, shapes: [shape])
        do {
            try phaseEngine.rootObject.addChild(occluder)
            logger.debug("📦 Room geometry: 5×4×5 m concrete box")
        } catch {
            logger.error("❌ Failed to attach room geometry — early reflections disabled: \(error.localizedDescription)")
        }
    }

    /// Start the PHASE audio engine.
    func start() throws {
        guard engineStatus != .running else { return }

        engineStatus = .starting
        do {
            try phaseEngine.start()
            engineStatus = .running
            logger.info("✅ PHASE engine started")
        } catch {
            engineStatus = .error(error.localizedDescription)
            throw SpatialAudioEngineError.phaseEngineStartFailed(underlying: error)
        }
    }

    /// Stop the PHASE engine and invalidate all active sound events.
    func stop() {
        guard engineStatus == .running else { return }

        let sources = sourcesLock.withLock { Array($0.values) }
        for source in sources {
            source.soundEvent.stopAndInvalidate()
        }
        phaseEngine.stop()
        engineStatus = .stopped
        if isHeadTrackingActive { disableHeadTracking() }
        logger.info("🛑 PHASE engine stopped")
    }

    // MARK: - Source Management

    func addSource(for processID: pid_t, format: AVAudioFormat) throws {
        let alreadyExists = sourcesLock.withLock { $0[processID] != nil }
        guard !alreadyExists else {
            throw SpatialAudioEngineError.sourceAlreadyExists(processID: processID)
        }

        logger.info("🔧 Adding PHASE source for PID \(processID) — \(format.sampleRate)Hz \(format.channelCount)ch")

        // Optional format conversion to engine format
        var converter: AVAudioConverter?
        if !isFormatCompatible(format) {
            logger.debug("   ⚡ Format mismatch — creating converter to \(self.engineFormat.sampleRate)Hz")
            guard let conv = AVAudioConverter(from: format, to: engineFormat) else {
                throw SpatialAudioEngineError.formatConversionFailed(
                    from: formatDescription(format),
                    to: formatDescription(engineFormat)
                )
            }
            converter = conv
        }

        // 1. Build PHASESpatialPipeline: direct path + early reflections + late reverb.
        //    The init returns nullable — flags == 0 produces nil, so we guard-unwrap.
        guard let spatialPipeline = PHASESpatialPipeline(flags: [.directPathTransmission, .earlyReflections, .lateReverb]) else {
            throw SpatialAudioEngineError.phaseSoundEventCreationFailed(processID: processID)
        }
        let mixerDef = PHASESpatialMixerDefinition(spatialPipeline: spatialPipeline)
        mixerDef.distanceModelParameters = PHASEGeometricSpreadingDistanceModelParameters()

        // 2. Register push stream node definition.
        //    Capture the auto-generated identifier before registration — we'll need
        //    it to retrieve the PHASEPushStreamNode from soundEvent.pushStreamNodes.
        let streamNodeDef = PHASEPushStreamNodeDefinition(
            mixerDefinition: mixerDef,
            format: engineFormat
        )
        let streamIdentifier = streamNodeDef.identifier

        do {
            try phaseEngine.assetRegistry.registerSoundEventAsset(
                rootNode: streamNodeDef,
                identifier: "event-\(processID)"
            )
        } catch {
            throw SpatialAudioEngineError.phaseAssetRegistrationFailed(processID: processID)
        }

        // 3. Create PHASESource positioned at the default center location.
        let source = PHASESource(engine: phaseEngine)
        let defaultPoint = SpatialPosition.center.scaledPoint(by: 2.0)
        source.transform = makeTransform(from: defaultPoint)
        do {
            try phaseEngine.rootObject.addChild(source)
        } catch {
            phaseEngine.assetRegistry.unregisterAsset(identifier: "event-\(processID)", completion: nil)
            throw SpatialAudioEngineError.phaseSoundEventCreationFailed(processID: processID)
        }

        // 4. Create sound event (binds source → listener via spatial mixer).
        let mixerParams = PHASEMixerParameters()
        mixerParams.addSpatialMixerParameters(
            identifier: mixerDef.identifier,
            source: source,
            listener: phaseListener
        )

        let soundEvent: PHASESoundEvent
        do {
            soundEvent = try PHASESoundEvent(
                engine: phaseEngine,
                assetIdentifier: "event-\(processID)",
                mixerParameters: mixerParams
            )
        } catch {
            phaseEngine.rootObject.removeChild(source)
            phaseEngine.assetRegistry.unregisterAsset(identifier: "event-\(processID)", completion: nil)
            throw SpatialAudioEngineError.phaseSoundEventCreationFailed(processID: processID)
        }

        // 5. Retrieve push stream node BEFORE start() so we can prime the queue.
        //    PHASESoundEvent.pushStreamNodes is populated at event creation, not at start.
        guard let pushStreamNode = soundEvent.pushStreamNodes[streamIdentifier] else {
            soundEvent.stopAndInvalidate()
            phaseEngine.rootObject.removeChild(source)
            phaseEngine.assetRegistry.unregisterAsset(identifier: "event-\(processID)", completion: nil)
            throw SpatialAudioEngineError.phaseSoundEventCreationFailed(processID: processID)
        }

        // 6. Prime the push stream queue with silence before start().
        //    PHASE's IOThread (com.apple.audio.IOThread.client) begins rendering the
        //    moment start() returns. If the queue is empty on the very first render cycle
        //    it dereferences a null "current buffer" pointer → EXC_BAD_ACCESS at 0x1.
        //    Scheduling 4096 frames of silence (85 ms) guarantees the queue is non-empty
        //    before the IOThread fires, with no perceptible impact on playback latency.
        if let primeBuffer = AVAudioPCMBuffer(pcmFormat: engineFormat, frameCapacity: 4096) {
            primeBuffer.frameLength = 4096
            pushStreamNode.scheduleBuffer(buffer: primeBuffer)
        }

        // 7. Start sound event now that the queue is primed.
        do {
            try soundEvent.start()
        } catch {
            soundEvent.stopAndInvalidate()
            phaseEngine.rootObject.removeChild(source)
            phaseEngine.assetRegistry.unregisterAsset(identifier: "event-\(processID)", completion: nil)
            throw SpatialAudioEngineError.phaseSoundEventCreationFailed(processID: processID)
        }

        let sourceNode = PHASESourceNode(
            source: source,
            soundEvent: soundEvent,
            pushStreamNode: pushStreamNode,
            converter: converter
        )

        let newCount = sourcesLock.withLock { (sources: inout [pid_t: PHASESourceNode]) -> Int in
            sources[processID] = sourceNode
            return sources.count
        }
        activeSourceCount = newCount
        sourcePresets[processID] = .center
        sourceModes[processID] = .ambienceBed
        sourceDistances[processID] = 2.0

        logger.info("✅ PHASE source added for PID \(processID)")
    }

    func removeSource(for processID: pid_t) {
        let result = sourcesLock.withLock { (sources: inout [pid_t: PHASESourceNode]) -> (PHASESourceNode, Int)? in
            guard let node = sources.removeValue(forKey: processID) else { return nil }
            return (node, sources.count)
        }
        guard let (sourceNode, newCount) = result else { return }

        sourceNode.soundEvent.stopAndInvalidate()
        phaseEngine.rootObject.removeChild(sourceNode.source)
        phaseEngine.assetRegistry.unregisterAsset(identifier: "event-\(processID)", completion: nil)

        activeSourceCount = newCount
        sourcePresets.removeValue(forKey: processID)
        sourceModes.removeValue(forKey: processID)
        sourceDistances.removeValue(forKey: processID)

        logger.info("🗑️ Removed PHASE source for PID \(processID)")
    }

    // MARK: - Spatial Positioning

    /// Move an audio source to a predefined position preset.
    /// Updates the PHASESource transform in the PHASE scene graph.
    func setPreset(_ preset: SpatialPosition, for processID: pid_t) {
        guard let sourceNode = sourcesLock.withLock({ $0[processID] }) else { return }
        let distance = sourceDistances[processID] ?? 1.0
        let point = preset.scaledPoint(by: distance)
        sourceNode.source.transform = makeTransform(from: point)
        sourcePresets[processID] = preset
        logger.info("📍 PID \(processID) → \(preset.rawValue) @ \(distance, privacy: .public)× (\(point.x, privacy: .public), \(point.y, privacy: .public), \(point.z, privacy: .public))")
    }

    /// Adjust how far from the listener the source is placed (in meters).
    /// PHASE's geometric spreading distance model attenuates naturally with distance.
    func setDistance(_ distance: Float, for processID: pid_t) {
        guard let sourceNode = sourcesLock.withLock({ $0[processID] }) else { return }
        let preset = sourcePresets[processID] ?? .center
        let point = preset.scaledPoint(by: distance)
        sourceNode.source.transform = makeTransform(from: point)
        sourceDistances[processID] = distance
        logger.info("📏 PID \(processID) → \(distance, privacy: .public) m")
    }

    /// Store the spatial rendering mode for UI display.
    /// PHASE pipeline is stereo for all sources in this version.
    func setSourceMode(_ mode: AVAudio3DMixingSourceMode, for processID: pid_t) {
        guard sourcesLock.withLock({ $0[processID] != nil }) else { return }
        // TODO(SPAT-40): implement mode-specific pipelines (pointSource = mono, ambienceBed = stereo)
        sourceModes[processID] = mode
        logger.info("🎙️ PID \(processID) mode → \(mode == .ambienceBed ? "ambienceBed" : "pointSource", privacy: .public) (stored; pipeline unchanged)")
    }

    // MARK: - Head Tracking

    /// Whether the connected headphones support motion updates.
    var isHeadTrackingAvailable: Bool {
        headphoneMotionManager.isDeviceMotionAvailable
    }

    /// Start streaming AirPods orientation into the PHASE listener transform.
    /// Sources appear fixed in world space as the listener rotates.
    func enableHeadTracking() {
        guard headphoneMotionManager.isDeviceMotionAvailable,
              !headphoneMotionManager.isDeviceMotionActive else { return }

        headphoneMotionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let motion, error == nil else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let q = motion.attitude.quaternion
                let rotation = simd_quaternion(Float(q.x), Float(q.y), Float(q.z), Float(q.w))
                var transform = simd_float4x4(rotation)
                transform.columns.3.w = 1
                self.phaseListener.transform = transform
            }
        }
        isHeadTrackingActive = true
        logger.info("🎧 Head tracking enabled")
    }

    /// Stop head tracking and reset the listener to the default forward orientation.
    func disableHeadTracking() {
        headphoneMotionManager.stopDeviceMotionUpdates()
        phaseListener.transform = matrix_identity_float4x4
        isHeadTrackingActive = false
        logger.info("🎧 Head tracking disabled")
    }

    // MARK: - Buffer Scheduling (nonisolated — called from IOProc-adjacent callback thread)

    /// Schedule an audio buffer for playback via PHASE push stream.
    /// Marked nonisolated so calls from the Core Audio IOProc-adjacent callback do NOT
    /// hop to the main actor. `sourcesLock` (OSAllocatedUnfairLock) is Sendable and
    /// provides the necessary thread safety for the shared sources dictionary.
    nonisolated func scheduleBuffer(_ buffer: AVAudioPCMBuffer, for processID: pid_t) {
        guard let sourceNode = sourcesLock.withLock({ $0[processID] }) else { return }

        // Backpressure: drop frames if PHASE render thread is slow
        guard sourceNode.pendingCount < 5 else { return }

        let bufferToSchedule: AVAudioPCMBuffer
        if let converter = sourceNode.converter {
            // TODO(Phase 8): Use a pre-allocated buffer pool to avoid per-call allocation
            guard let converted = convertBuffer(buffer, using: converter) else { return }
            bufferToSchedule = converted
        } else {
            bufferToSchedule = buffer
        }

        sourceNode.pushStreamNode.scheduleBuffer(
            buffer: bufferToSchedule,
            completionCallbackType: .dataRendered
        ) { [weak self] _ in
            self?.handleBufferCompleted(for: processID)
        }

        sourceNode.incrementScheduled()
    }

    private nonisolated func handleBufferCompleted(for processID: pid_t) {
        sourcesLock.withLock { $0[processID]?.incrementRendered() }
    }

    // MARK: - Format Utilities

    private func isFormatCompatible(_ format: AVAudioFormat) -> Bool {
        return format.sampleRate == engineFormat.sampleRate
            && format.channelCount == engineFormat.channelCount
            && format.commonFormat == engineFormat.commonFormat
            && !format.isInterleaved    // engineFormat is non-interleaved; interleaved taps must be converted
    }

    private func formatDescription(_ format: AVAudioFormat) -> String {
        "\(format.sampleRate)Hz \(format.channelCount)ch"
    }

    /// Convert an AVAudio3DPoint to a PHASE simd_float4x4 homogeneous transform.
    /// PHASE uses a Y-up right-hand coordinate system matching OpenAL — no axis conversion needed.
    private func makeTransform(from point: AVAudio3DPoint) -> simd_float4x4 {
        var t = matrix_identity_float4x4
        t.columns.3 = simd_float4(point.x, point.y, point.z, 1)
        return t
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
}

// MARK: - PHASE Source Node

/// Holds all PHASE objects for a single captured audio process.
///
/// `@unchecked Sendable` because instances are accessed exclusively through
/// `sourcesLock` (OSAllocatedUnfairLock), which provides the necessary synchronisation.
private class PHASESourceNode: @unchecked Sendable {
    /// PHASEObject placed in the PHASE scene graph for 3D positioning.
    let source: PHASESource
    /// Running sound event that routes audio through the spatial pipeline.
    let soundEvent: PHASESoundEvent
    /// Receives raw PCM buffers from the Core Audio Tap. `nonisolated let` —
    /// constant after init, safe to read from the IOProc-adjacent callback thread.
    nonisolated let pushStreamNode: PHASEPushStreamNode
    let converter: AVAudioConverter?

    /// Protects scheduled/rendered buffer counts accessed from multiple threads:
    /// - incrementScheduled: IOProc-adjacent callback thread (scheduleBuffer)
    /// - incrementRendered: PHASE render completion callback
    /// - pendingCount: IOProc-adjacent callback thread (backpressure check)
    private let countLock = OSAllocatedUnfairLock(initialState: (scheduled: 0, rendered: 0))

    nonisolated var pendingCount: Int {
        countLock.withLock { $0.scheduled - $0.rendered }
    }

    nonisolated func incrementScheduled() {
        countLock.withLock { $0.scheduled += 1 }
    }

    nonisolated func incrementRendered() {
        countLock.withLock { $0.rendered += 1 }
    }

    init(
        source: PHASESource,
        soundEvent: PHASESoundEvent,
        pushStreamNode: PHASEPushStreamNode,
        converter: AVAudioConverter?
    ) {
        self.source = source
        self.soundEvent = soundEvent
        self.pushStreamNode = pushStreamNode
        self.converter = converter
    }
}
