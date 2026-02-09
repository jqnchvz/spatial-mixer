//
//  MenuBarView.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 09-02-26.
//

import SwiftUI

struct MenuBarView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("Spatial Mixer")
                .font(.headline)
            
            Divider()
            
            // Audio Sources Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Audio Sources")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("No apps detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
}

#Preview {
    MenuBarView()
}
