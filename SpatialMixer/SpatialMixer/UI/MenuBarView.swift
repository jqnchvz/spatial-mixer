//
//  MenuBarView.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 09-02-26.
//

import SwiftUI

struct MenuBarView: View {
    @StateObject private var permissions = AudioPermissions()
    
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
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .imageScale(.medium)
                        Text("Permission Required")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
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
