//
//  SpatialMixerApp.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 09-02-26.
//

import SwiftUI

@main
struct SpatialMixerApp: App {
    /// Single coordinator that owns all audio infrastructure.
    /// Shared between the MenuBarExtra and the settings Window via environmentObject.
    @StateObject private var coordinator = AudioSessionCoordinator()

    var body: some Scene {
        MenuBarExtra("Spatial Mixer", systemImage: "waveform.circle") {
            MenuBarView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.spatialEngine)
                .environmentObject(coordinator.processDiscovery)
                .environmentObject(coordinator.permissions)
        }

        Window("Spatial Mixer", id: "settings") {
            SettingsWindowView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.spatialEngine)
                .environmentObject(coordinator.processDiscovery)
        }
        .defaultSize(width: 580, height: 500)
        .defaultPosition(.center)
    }
}
