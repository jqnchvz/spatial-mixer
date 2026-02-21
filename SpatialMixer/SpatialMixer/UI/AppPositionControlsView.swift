//
//  AppPositionControlsView.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 21-02-26.
//

import SwiftUI
import AVFoundation

/// Compact position preset + source mode controls shown per captured app.
struct AppPositionControlsView: View {
    let processID: pid_t
    @ObservedObject var spatialEngine: SpatialAudioEngine

    private var selectedPreset: SpatialPosition {
        spatialEngine.sourcePresets[processID] ?? .center
    }

    private var isPointSource: Bool {
        spatialEngine.sourceModes[processID] == .pointSource
    }

    private var currentDistance: Float {
        spatialEngine.sourceDistances[processID] ?? 1.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Position presets
            HStack(spacing: 0) {
                Text("Pos")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 26, alignment: .leading)

                HStack(spacing: 3) {
                    ForEach(SpatialPosition.allCases) { preset in
                        Button(preset.shortLabel) {
                            spatialEngine.setPreset(preset, for: processID)
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .tint(selectedPreset == preset ? Color.accentColor : Color.secondary)
                        .controlSize(.mini)
                    }
                }
            }

            // Source mode toggle
            HStack(spacing: 0) {
                Text("Mode")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 26, alignment: .leading)

                HStack(spacing: 3) {
                    Button("Ambience") {
                        spatialEngine.setSourceMode(.ambienceBed, for: processID)
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .tint(isPointSource ? Color.secondary : Color.accentColor)
                    .controlSize(.mini)

                    Button("Point") {
                        spatialEngine.setSourceMode(.pointSource, for: processID)
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .tint(isPointSource ? Color.accentColor : Color.secondary)
                    .controlSize(.mini)
                }
            }

            // Distance control — label/value row above, full-width slider below.
            // Keeping the Slider in its own row avoids the HStack space-competition
            // that makes it invisible or pushes the value label off-screen.
            VStack(spacing: 2) {
                HStack {
                    Text("Dist")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(currentDistance.rounded())) m")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(currentDistance) },
                        set: { spatialEngine.setDistance(Float($0), for: processID) }
                    ),
                    in: 1.0...10.0,
                    step: 0.5
                )
                .controlSize(.small)
            }
        }
        .padding(.leading, 24) // indent to align with app name
    }
}
