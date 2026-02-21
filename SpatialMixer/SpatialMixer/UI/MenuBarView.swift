//
//  MenuBarView.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 09-02-26.
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var coordinator: AudioSessionCoordinator
    @EnvironmentObject var spatialEngine: SpatialAudioEngine
    @EnvironmentObject var processDiscovery: ProcessDiscovery
    @EnvironmentObject var permissions: AudioPermissions

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("Spatial Mixer")
                .font(.headline)

            Divider()

            // Permission warning
            if !permissions.screenCaptureGranted {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("⚠️").font(.system(size: 18))
                        Text("Permission Required")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    Text("Screen recording permission is needed to capture app audio.")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Grant Permission") { permissions.requestPermission() }
                        .buttonStyle(.borderedProminent)
                    Button("Open System Settings") { permissions.openSystemSettings() }
                        .font(.caption).buttonStyle(.link)
                }
                .padding(.vertical, 4)
                Divider()
            }

            // Engine status
            HStack(spacing: 8) {
                Circle()
                    .fill(engineStatusColor)
                    .frame(width: 8, height: 8)
                Text(engineStatusText)
                    .font(.caption).foregroundColor(.secondary)
            }

            if let error = coordinator.engineError {
                Text("Error: \(error)")
                    .font(.caption2).foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Audio Sources
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Audio Sources")
                        .font(.subheadline).fontWeight(.medium)
                    Spacer()
                    Text("\(spatialEngine.activeSourceCount) active")
                        .font(.caption2).foregroundColor(.secondary)
                }

                if processDiscovery.runningApps.isEmpty {
                    Text("No apps detected")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(processDiscovery.runningApps) { app in
                        HStack(spacing: 8) {
                            Image(nsImage: app.icon)
                                .resizable().frame(width: 16, height: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name).font(.caption)
                                if coordinator.activeTapProcesses.contains(app.processID) {
                                    Text("🎧 Capturing")
                                        .font(.caption2).foregroundColor(.green)
                                }
                            }

                            Spacer()

                            if coordinator.activeTapProcesses.contains(app.processID) {
                                Button("Stop") { coordinator.stopTap(for: app.processID) }
                                    .buttonStyle(.borderless).font(.caption2)
                            } else {
                                Button("Capture") { coordinator.startTap(for: app) }
                                    .buttonStyle(.borderless).font(.caption2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Divider()

            // Open Settings
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                HStack {
                    Text("Open Settings")
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Divider()

            Button("Quit Spatial Mixer") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Helpers

    private var engineStatusColor: Color {
        switch spatialEngine.engineStatus {
        case .stopped:  return .gray
        case .starting: return .orange
        case .running:  return .green
        case .error:    return .red
        }
    }

    private var engineStatusText: String {
        switch spatialEngine.engineStatus {
        case .stopped:  return "Engine Stopped"
        case .starting: return "Engine Starting..."
        case .running:  return "Engine Running"
        case .error:    return "Engine Error"
        }
    }
}
