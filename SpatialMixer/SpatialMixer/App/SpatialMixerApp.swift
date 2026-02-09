//
//  SpatialMixerApp.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 09-02-26.
//

import SwiftUI

@main
struct SpatialMixerApp: App {
    var body: some Scene {
        MenuBarExtra("Spatial Mixer", systemImage: "waveform.circle") {
            MenuBarView()
        }
    }
}
