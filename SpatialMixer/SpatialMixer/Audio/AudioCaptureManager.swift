//
//  AudioCaptureManager.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 09-02-26.
//

import Foundation
import CoreAudio
import AVFoundation
import Combine

/// Manages Core Audio Taps for per-application audio capture
@MainActor
class AudioCaptureManager: ObservableObject {
    /// Active audio taps by process ID
    @Published private(set) var activeTaps: [pid_t: AudioTap] = [:]

    /// Create an audio tap for a specific process
    func createTap(for processID: pid_t) throws -> AudioTap {
        // Check if tap already exists
        if let existingTap = activeTaps[processID] {
            return existingTap
        }

        // Create new tap
        let tap = try AudioTap(processID: processID)
        activeTaps[processID] = tap

        return tap
    }

    /// Remove audio tap for a process
    func removeTap(for processID: pid_t) {
        if let tap = activeTaps[processID] {
            tap.stop()
            activeTaps.removeValue(forKey: processID)
        }
    }

    /// Remove all taps
    func removeAllTaps() {
        for (_, tap) in activeTaps {
            tap.stop()
        }
        activeTaps.removeAll()
    }
}

/// Represents a single Core Audio Tap for an application
class AudioTap {
    let processID: pid_t
    private var tapID: AudioObjectID = 0
    private var isRunning = false

    /// Audio buffer handler
    var bufferHandler: ((AVAudioPCMBuffer) -> Void)?

    init(processID: pid_t) throws {
        self.processID = processID

        // Convert PID to AudioObjectID
        let audioObjectID = try Self.translatePIDToAudioObject(pid: processID)

        // Create the tap
        try createHardwareTap(for: audioObjectID)
    }

    /// Translate process ID to AudioObjectID
    private static func translatePIDToAudioObject(pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var processObjectID: AudioObjectID = 0
        var pidValue = pid
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pidValue,
            &size,
            &processObjectID
        )

        guard status == noErr else {
            throw AudioTapError.translationFailed(status: status)
        }

        return processObjectID
    }

    /// Create the hardware process tap
    private func createHardwareTap(for processObjectID: AudioObjectID) throws {
        // Create tap description for stereo mix of this process
        let tapDescription = CATapDescription(
            stereoMixdownOfProcesses: [processObjectID]
        )

        tapDescription.name = "SpatialMixer Tap \(processID)"
        // muteBehavior defaults to unmuted (0), so audio plays normally while tapped

        // Create the tap
        var newTapID: AudioObjectID = 0
        let status = AudioHardwareCreateProcessTap(tapDescription, &newTapID)

        guard status == noErr else {
            throw AudioTapError.creationFailed(status: status)
        }

        self.tapID = newTapID
        self.isRunning = true
    }

    /// Start the tap
    func start() {
        guard !isRunning else { return }
        // Tap starts automatically when created
        isRunning = true
    }

    /// Stop the tap and destroy it
    func stop() {
        guard isRunning else { return }

        if tapID != 0 {
            // Destroy the tap using the proper API
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }

        isRunning = false
    }

    deinit {
        stop()
    }
}

/// Errors that can occur during audio tap operations
enum AudioTapError: Error, LocalizedError {
    case translationFailed(status: OSStatus)
    case creationFailed(status: OSStatus)
    case tapNotAvailable

    var errorDescription: String? {
        switch self {
        case .translationFailed(let status):
            return "Failed to translate PID to AudioObjectID: \(status)"
        case .creationFailed(let status):
            return "Failed to create audio tap: \(status)"
        case .tapNotAvailable:
            return "Audio tap not available for this process"
        }
    }
}

