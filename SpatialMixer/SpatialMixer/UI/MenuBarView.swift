//
//  MenuBarView.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 09-02-26.
//

import SwiftUI
import AVFoundation

struct MenuBarView: View {
    @StateObject private var permissions = AudioPermissions()
    @StateObject private var processDiscovery = ProcessDiscovery()
    @StateObject private var captureManager = AudioCaptureManager()
    @StateObject private var spatialEngine = SpatialAudioEngine()

    @State private var activeTapProcesses: Set<pid_t> = []
    @State private var engineError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("Spatial Mixer")
                .font(.headline)
            
            Divider()
            
            // Permission Status Section
            if !permissions.screenCaptureGranted {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("⚠️")
                            .font(.system(size: 18))
                        Text("Permission Required")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    Text("Screen recording permission is needed to capture app audio.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Button("Grant Permission") {
                        permissions.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Open System Settings") {
                        permissions.openSystemSettings()
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
                .padding(.vertical, 4)
                
                Divider()
            }

            // Engine Status
            HStack(spacing: 8) {
                Circle()
                    .fill(engineStatusColor)
                    .frame(width: 8, height: 8)

                Text(engineStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let error = engineError {
                Text("Error: \(error)")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Audio Sources Section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Audio Sources")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Text("\(spatialEngine.activeSourceCount) active")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if processDiscovery.runningApps.isEmpty {
                    Text("No apps detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(processDiscovery.runningApps) { app in
                        HStack(spacing: 8) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 16, height: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.caption)

                                if activeTapProcesses.contains(app.processID) {
                                    Text("🎧 Capturing")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }

                            Spacer()

                            // Tap control button
                            if activeTapProcesses.contains(app.processID) {
                                Button("Stop") {
                                    stopTap(for: app.processID)
                                }
                                .buttonStyle(.borderless)
                                .font(.caption2)
                            } else {
                                Button("Capture") {
                                    startTap(for: app)
                                }
                                .buttonStyle(.borderless)
                                .font(.caption2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            
            Divider()
            
            // Settings Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Coming soon...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Quit Button
            Button("Quit Spatial Mixer") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Computed Properties

    private var engineStatusColor: Color {
        switch spatialEngine.engineStatus {
        case .stopped:
            return .gray
        case .starting:
            return .orange
        case .running:
            return .green
        case .error:
            return .red
        }
    }

    private var engineStatusText: String {
        switch spatialEngine.engineStatus {
        case .stopped:
            return "Engine Stopped"
        case .starting:
            return "Engine Starting..."
        case .running:
            return "Engine Running"
        case .error(let message):
            return "Engine Error"
        }
    }

    // MARK: - Tap Management

    /// Start capturing audio from an app
    private func startTap(for app: AppInfo) {
        print("🔵 startTap called for \(app.name) (PID: \(app.processID))")

        do {
            // Start engine if not running
            if spatialEngine.engineStatus != .running {
                print("🎵 Starting spatial audio engine...")
                try spatialEngine.start()
                engineError = nil
            }

            // Create Core Audio Tap
            let tap = try captureManager.createTap(for: app.processID)

            guard let format = tap.audioFormat else {
                throw AudioTapError.formatNotAvailable
            }

            // Add source to spatial engine
            try spatialEngine.addSource(for: app.processID, format: format)

            // Set up buffer handler to pipe audio to engine
            let appName = app.name
            let processID = app.processID
            var bufferCount = 0

            tap.bufferHandler = { [weak spatialEngine] (buffer: AVAudioPCMBuffer) in
                // Schedule buffer for spatial playback
                // This is called from IOProc queue - scheduleBuffer is thread-safe
                spatialEngine?.scheduleBuffer(buffer, for: processID)

                bufferCount += 1
                if bufferCount == 1 {
                    print("✅ FIRST BUFFER RECEIVED for \(appName)!")
                    print("   Format: \(buffer.format)")
                    print("   Frame length: \(buffer.frameLength)")
                    print("   Channel count: \(buffer.format.channelCount)")
                    print("   Sample rate: \(buffer.format.sampleRate) Hz")
                    print("   🎧 Audio now playing through spatial engine")
                }
            }

            activeTapProcesses.insert(app.processID)
            print("✓ Started tap for \(app.name) (PID: \(app.processID))")

        } catch {
            engineError = error.localizedDescription
            print("✗ Failed to start tap for \(app.name): \(error.localizedDescription)")
        }
    }

    /// Stop capturing audio from an app
    private func stopTap(for processID: pid_t) {
        // Remove from spatial engine
        spatialEngine.removeSource(for: processID)

        // Remove Core Audio Tap
        captureManager.removeTap(for: processID)

        activeTapProcesses.remove(processID)
        print("✓ Stopped tap for process \(processID)")

        // Stop engine if no more sources
        if activeTapProcesses.isEmpty {
            spatialEngine.stop()
            print("🛑 Stopped engine (no active sources)")
        }
    }
}

#Preview {
    MenuBarView()
}
