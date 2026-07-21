//
//  SettingsWindowView.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 21-02-26.
//

import SwiftUI
import AVFoundation

/// Main configuration window opened from the menu bar.
/// Shows per-source spatial controls and global settings.
struct SettingsWindowView: View {
    @EnvironmentObject var coordinator: AudioSessionCoordinator
    @EnvironmentObject var spatialEngine: SpatialAudioEngine
    @EnvironmentObject var processDiscovery: ProcessDiscovery

    /// Captured apps in the same order as the process discovery list.
    private var capturedApps: [AppInfo] {
        processDiscovery.runningApps.filter {
            coordinator.activeTapProcesses.contains($0.processID)
        }
    }

    var body: some View {
        HSplitView {
            // Left panel: per-source controls
            sourcesPanel
                .frame(minWidth: 320, idealWidth: 360)

            // Right panel: spatial diagram + global settings
            VStack(spacing: 0) {
                diagramPanel
                Divider()
                globalSettingsPanel
            }
            .frame(minWidth: 200, idealWidth: 220)
        }
        .frame(minHeight: 420)
    }

    // MARK: - Sources Panel

    private var sourcesPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if capturedApps.isEmpty {
                    emptyState
                } else {
                    ForEach(capturedApps) { app in
                        sourceRow(for: app)
                        if app.id != capturedApps.last?.id {
                            Divider().padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No apps being captured")
                .font(.headline)
            Text("Use the menu bar icon to start\ncapturing an app's audio.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func sourceRow(for app: AppInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // App header
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.headline)
                    Text("PID \(app.processID)")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Button("Stop") { coordinator.stopTap(for: app.processID) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Spatial controls
            AppPositionControlsView(processID: app.processID)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Spatial Diagram Panel

    private var diagramPanel: some View {
        VStack(spacing: 8) {
            Text("Spatial Map")
                .font(.caption)
                .foregroundColor(.secondary)

            SpatialDiagramView(
                capturedApps: capturedApps,
                spatialEngine: spatialEngine
            )
            .frame(width: 180, height: 180)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    // MARK: - Global Settings Panel

    private var globalSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)

            // Head tracking
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Head Tracking")
                        .font(.caption)
                    Text(spatialEngine.isHeadTrackingAvailable
                         ? "AirPods detected"
                         : "Connect AirPods Pro or Max")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { spatialEngine.isHeadTrackingActive },
                    set: { enabled in
                        if enabled { spatialEngine.enableHeadTracking() }
                        else { spatialEngine.disableHeadTracking() }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!spatialEngine.isHeadTrackingAvailable)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Spatial Diagram

/// Top-down 2D view of the listening space.
/// The listener sits at the centre; each captured source is plotted by its X/Z coordinates.
struct SpatialDiagramView: View {
    let capturedApps: [AppInfo]
    @ObservedObject var spatialEngine: SpatialAudioEngine

    /// Coordinate range shown on each axis (±range maps to the full canvas).
    private let range: Float = 12.0

    var body: some View {
        Canvas { context, size in
            let cx = size.width  / 2
            let cy = size.height / 2

            // Background
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(NSColor.controlBackgroundColor))
            )

            // Grid rings
            for r in stride(from: 0.25, through: 1.0, by: 0.25) {
                let radius = CGFloat(r) * min(cx, cy) * 0.9
                context.stroke(
                    Path { p in p.addEllipse(in: CGRect(x: cx - radius, y: cy - radius,
                                                         width: radius * 2, height: radius * 2)) },
                    with: .color(.secondary.opacity(0.2)),
                    lineWidth: 0.5
                )
            }

            // Axis lines
            let axisColor = Color.secondary.opacity(0.2)
            context.stroke(Path { p in p.move(to: CGPoint(x: cx, y: 0)); p.addLine(to: CGPoint(x: cx, y: size.height)) },
                           with: .color(axisColor), lineWidth: 0.5)
            context.stroke(Path { p in p.move(to: CGPoint(x: 0, y: cy)); p.addLine(to: CGPoint(x: size.width, y: cy)) },
                           with: .color(axisColor), lineWidth: 0.5)

            // Listener dot (always at centre)
            let listenerRadius: CGFloat = 7
            context.fill(
                Path(ellipseIn: CGRect(x: cx - listenerRadius, y: cy - listenerRadius,
                                       width: listenerRadius * 2, height: listenerRadius * 2)),
                with: .color(.accentColor)
            )

            // Source dots — OpenAL: +X = right, -Z = front (towards viewer in top-down)
            for app in capturedApps {
                guard let preset = spatialEngine.sourcePresets[app.processID],
                      let distance = spatialEngine.sourceDistances[app.processID] else { continue }

                let point = preset.scaledPoint(by: distance)
                let scale = CGFloat(min(cx, cy) * 0.9) / CGFloat(range)
                // x maps to horizontal axis; -z maps to vertical (front = up in diagram)
                let sx = cx + CGFloat(point.x)  * scale
                let sy = cy - CGFloat(point.z)  * scale  // -z = front = top

                let sourceRadius: CGFloat = 6
                let dotRect = CGRect(x: sx - sourceRadius, y: sy - sourceRadius,
                                     width: sourceRadius * 2, height: sourceRadius * 2)
                context.fill(Path(ellipseIn: dotRect), with: .color(.orange))

                // App name label
                context.draw(
                    Text(app.name).font(.system(size: 8)).foregroundColor(.primary),
                    at: CGPoint(x: sx, y: sy - sourceRadius - 6)
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
    }
}

#Preview {
    SettingsWindowView()
        .environmentObject(AudioSessionCoordinator())
}
