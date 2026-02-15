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

    @State private var activeTapProcesses: Set<pid_t> = []

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
            
            // Audio Sources Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Audio Sources")
                    .font(.subheadline)
                    .fontWeight(.medium)

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

    // MARK: - Tap Management

    /// Start capturing audio from an app
    private func startTap(for app: AppInfo) {
        print("🔵 startTap called for \(app.name) (PID: \(app.processID))")

        do {
            let tap = try captureManager.createTap(for: app.processID)

            // Set up buffer handler to log received audio
            let appName = app.name
            let processID = app.processID
            var bufferCount = 0

            tap.bufferHandler = { buffer in
                bufferCount += 1
                if bufferCount == 1 {
                    print("✅ FIRST BUFFER RECEIVED for \(appName)!")
                    print("   Format: \(buffer.format)")
                    print("   Frame length: \(buffer.frameLength)")
                    print("   Channel count: \(buffer.format.channelCount)")
                    print("   Sample rate: \(buffer.format.sampleRate) Hz")
                } else if bufferCount % 100 == 0 {
                    print("📊 \(appName): \(bufferCount) buffers received")
                }
            }

            activeTapProcesses.insert(app.processID)
            print("✓ Started tap for \(app.name) (PID: \(app.processID))")

        } catch {
            print("✗ Failed to create tap for \(app.name): \(error.localizedDescription)")
        }
    }

    /// Stop capturing audio from an app
    private func stopTap(for processID: pid_t) {
        captureManager.removeTap(for: processID)
        activeTapProcesses.remove(processID)
        print("✓ Stopped tap for process \(processID)")
    }
}

#Preview {
    MenuBarView()
}
