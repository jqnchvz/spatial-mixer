//
//  AudioCaptureManager.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 11-02-26.
//

import Foundation
import CoreAudio
import AVFoundation
import Combine

/// Manages Core Audio Taps for per-application audio capture
@MainActor
class AudioCaptureManager: ObservableObject {
    @Published private(set) var activeTaps: [pid_t: AudioTap] = [:]

    /// Create a new tap for the specified process
    func createTap(for processID: pid_t) throws -> AudioTap {
        // Return existing tap if already created
        if let existingTap = activeTaps[processID] {
            return existingTap
        }

        // Create new tap
        let tap = try AudioTap(processID: processID)
        activeTaps[processID] = tap

        return tap
    }

    /// Remove and destroy a tap
    func removeTap(for processID: pid_t) {
        if let tap = activeTaps.removeValue(forKey: processID) {
            tap.stop()
        }
    }

    /// Remove all taps
    func removeAllTaps() {
        for tap in activeTaps.values {
            tap.stop()
        }
        activeTaps.removeAll()
    }
}

/// Represents a single Core Audio Tap for an application
class AudioTap {
    let processID: pid_t
    private var tapID: AudioObjectID = 0
    private var aggregateDeviceID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var tapUUID: UUID?
    private var isRunning = false

    /// The audio format of the tap
    private(set) var audioFormat: AVAudioFormat?

    /// Audio buffer handler - called on main thread with captured audio
    var bufferHandler: ((AVAudioPCMBuffer) -> Void)?

    /// Frame counter for debugging
    private var frameCounter: UInt64 = 0

    init(processID: pid_t) throws {
        self.processID = processID

        do {
            // Step 1: Translate PID to AudioObjectID
            let audioObjectID = try Self.translatePIDToAudioObject(pid: processID)

            // Step 2: Create the Core Audio Tap
            try createHardwareTap(for: audioObjectID)

            // Step 3: Read tap format and create aggregate device
            try setupAggregateDevice()

            // Step 4: Set up IO proc callback
            try setupIOProc()

        } catch {
            cleanup()
            throw error
        }
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

        guard status == noErr, processObjectID != 0 else {
            throw AudioTapError.translationFailed(status: status)
        }

        return processObjectID
    }

    /// Create the hardware process tap
    private func createHardwareTap(for processObjectID: AudioObjectID) throws {
        let tapDescription = CATapDescription(
            stereoMixdownOfProcesses: [processObjectID]
        )

        // CRITICAL: Set UUID explicitly (AudioCap does this)
        let uuid = UUID()
        tapDescription.uuid = uuid
        tapDescription.name = "SpatialMixer Tap \(processID)"

        self.tapUUID = uuid

        var newTapID: AudioObjectID = 0
        let status = AudioHardwareCreateProcessTap(tapDescription, &newTapID)

        guard status == noErr else {
            throw AudioTapError.creationFailed(status: status)
        }

        self.tapID = newTapID
        self.isRunning = true
    }

    /// Set up aggregate device for audio streaming
    private func setupAggregateDevice() throws {
        // Step 1: Read the tap's audio format
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var status = AudioObjectGetPropertyData(
            tapID,
            &formatAddress,
            0,
            nil,
            &size,
            &asbd
        )

        guard status == noErr else {
            throw AudioTapError.formatReadFailed(status: status)
        }

        self.audioFormat = AVAudioFormat(streamDescription: &asbd)

        // Step 2: Get the tap UUID
        guard let tapUUID = self.tapUUID else {
            throw AudioTapError.uidReadFailed(status: -1)
        }

        // Step 3: Get the default output device UID
        var defaultOutputID = AudioObjectID(kAudioObjectUnknown)
        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            0,
            nil,
            &propertySize,
            &defaultOutputID
        )

        guard status == noErr, defaultOutputID != kAudioObjectUnknown else {
            throw AudioTapError.deviceNotFound
        }

        // Get the device UID
        var deviceUIDAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var outputUID: CFString?
        var outputUIDSize = UInt32(MemoryLayout<CFString>.size)
        status = AudioObjectGetPropertyData(
            defaultOutputID,
            &deviceUIDAddress,
            0,
            nil,
            &outputUIDSize,
            &outputUID
        )

        guard status == noErr, let outputDeviceUID = outputUID as String? else {
            throw AudioTapError.deviceNotFound
        }

        // Step 4: Create aggregate device with tap and output
        let aggregateDict: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "SpatialMixer Aggregate \(processID)",
            kAudioAggregateDeviceUIDKey as String: "com.spatialmixer.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey as String: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey as String: NSNumber(value: true),
            kAudioAggregateDeviceIsStackedKey as String: NSNumber(value: false),
            kAudioAggregateDeviceTapAutoStartKey as String: NSNumber(value: true),
            kAudioAggregateDeviceSubDeviceListKey as String: [
                [kAudioSubDeviceUIDKey as String: outputDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapDriftCompensationKey as String: NSNumber(value: true),
                    kAudioSubTapUIDKey as String: tapUUID.uuidString
                ]
            ]
        ]

        var newAggregateID: AudioObjectID = 0
        status = AudioHardwareCreateAggregateDevice(aggregateDict as CFDictionary, &newAggregateID)

        guard status == noErr else {
            throw AudioTapError.aggregateDeviceCreationFailed(status: status)
        }

        self.aggregateDeviceID = newAggregateID
    }

    /// Set up IO proc callback for receiving audio frames
    private func setupIOProc() throws {
        guard let format = audioFormat else {
            throw AudioTapError.formatNotAvailable
        }

        let queue = DispatchQueue(label: "com.spatialmixer.ioProc.\(processID)", qos: .userInteractive)

        var newIOProcID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &newIOProcID,
            aggregateDeviceID,
            queue
        ) { [weak self] (
            inNow: UnsafePointer<AudioTimeStamp>,
            inInputData: UnsafePointer<AudioBufferList>,
            inInputTime: UnsafePointer<AudioTimeStamp>,
            outOutputData: UnsafeMutablePointer<AudioBufferList>,
            inOutputTime: UnsafePointer<AudioTimeStamp>
        ) in
            guard let self = self else { return }
            guard let handler = self.bufferHandler else { return }

            let bufferList = inInputData.pointee
            let bufferCount = Int(bufferList.mNumberBuffers)

            guard bufferCount > 0 else { return }

            withUnsafePointer(to: bufferList.mBuffers) { buffersPtr in
                let firstBuffer = UnsafeRawPointer(buffersPtr).assumingMemoryBound(to: AudioBuffer.self).pointee
                let frameCount = firstBuffer.mDataByteSize / UInt32(format.streamDescription.pointee.mBytesPerFrame)

                self.frameCounter += UInt64(frameCount)

                guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
                    return
                }

                pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

                let channelCount = Int(format.channelCount)
                for channel in 0..<channelCount {
                    if channel < bufferCount {
                        let sourcePtr = UnsafeRawPointer(buffersPtr).advanced(by: channel * MemoryLayout<AudioBuffer>.stride)
                            .assumingMemoryBound(to: AudioBuffer.self)
                        let sourceBuffer = sourcePtr.pointee

                        if let sourceData = sourceBuffer.mData,
                           let destData = pcmBuffer.floatChannelData?[channel] {
                            let byteCount = Int(sourceBuffer.mDataByteSize)
                            memcpy(destData, sourceData, byteCount)
                        }
                    }
                }

                DispatchQueue.main.async {
                    handler(pcmBuffer)
                }
            }
        }

        guard status == noErr, let procID = newIOProcID else {
            throw AudioTapError.ioProcCreationFailed(status: status)
        }

        self.ioProcID = procID

        // Start the aggregate device (with retry)
        var startStatus: OSStatus = noErr
        var attempts = 0
        let maxAttempts = 5

        repeat {
            if attempts > 0 {
                Thread.sleep(forTimeInterval: 0.05)
            }
            startStatus = AudioDeviceStart(aggregateDeviceID, procID)
            attempts += 1
        } while startStatus != noErr && attempts < maxAttempts

        guard startStatus == noErr else {
            throw AudioTapError.deviceStartFailed(status: startStatus)
        }
    }

    /// Stop the tap and destroy resources
    func stop() {
        guard isRunning else { return }
        cleanup()
        isRunning = false
    }

    /// Internal cleanup helper
    private func cleanup() {
        if let procID = ioProcID, aggregateDeviceID != 0 {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            ioProcID = nil
        }

        if aggregateDeviceID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = 0
        }

        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
    }
}

/// Errors that can occur during audio tap operations
enum AudioTapError: Error, LocalizedError {
    case translationFailed(status: OSStatus)
    case creationFailed(status: OSStatus)
    case tapNotAvailable
    case formatReadFailed(status: OSStatus)
    case uidReadFailed(status: OSStatus)
    case aggregateDeviceCreationFailed(status: OSStatus)
    case formatNotAvailable
    case ioProcCreationFailed(status: OSStatus)
    case deviceStartFailed(status: OSStatus)
    case deviceNotFound

    var errorDescription: String? {
        switch self {
        case .translationFailed(let status):
            return "Failed to translate PID to AudioObjectID: \(status)"
        case .creationFailed(let status):
            return "Failed to create audio tap: \(status)"
        case .tapNotAvailable:
            return "Audio tap not available for this process"
        case .formatReadFailed(let status):
            return "Failed to read tap audio format: \(status)"
        case .uidReadFailed(let status):
            return "Failed to read tap UID: \(status)"
        case .aggregateDeviceCreationFailed(let status):
            return "Failed to create aggregate device: \(status)"
        case .formatNotAvailable:
            return "Audio format not available"
        case .ioProcCreationFailed(let status):
            return "Failed to create IO proc callback: \(status)"
        case .deviceStartFailed(let status):
            return "Failed to start aggregate device: \(status)"
        case .deviceNotFound:
            return "Default audio output device not found"
        }
    }
}
