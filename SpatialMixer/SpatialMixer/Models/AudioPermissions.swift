//
//  AudioPermissions.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 09-02-26.
//

import Foundation
import Combine
import ScreenCaptureKit

@MainActor
class AudioPermissions: ObservableObject {
    @Published var screenCaptureGranted = false
    @Published var isChecking = false
    
    init() {
        checkPermission()
    }
    
    /// Check if screen capture permission is already granted
    func checkPermission() {
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
    }
    
    /// Request screen capture permission from the user
    /// This triggers the system permission dialog
    func requestPermission() {
        isChecking = true
        
        // CGRequestScreenCaptureAccess() shows system dialog
        // Returns true if permission granted, false otherwise
        let granted = CGRequestScreenCaptureAccess()
        
        screenCaptureGranted = granted
        isChecking = false
    }
    
    /// Open System Settings to the Screen Recording permissions pane
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
