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
            Text("Spatial Mixer")
                .font(.headline)
            
            Divider()
            
            Text("No audio sources detected")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(minWidth: 200)
    }
}

#Preview {
    MenuBarView()
}
