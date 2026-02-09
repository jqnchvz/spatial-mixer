//
//  AppInfo.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 09-02-26.
//

import AppKit

/// Represents a running macOS application with audio capability
struct AppInfo: Identifiable, Hashable {
    /// Unique identifier (uses process ID)
    let id: pid_t

    /// Human-readable application name
    let name: String

    /// Bundle identifier (e.g., com.apple.Safari)
    let bundleIdentifier: String?

    /// Application icon
    let icon: NSImage

    /// Process ID for Core Audio Taps
    let processID: pid_t

    /// Initialize from NSRunningApplication
    init(from app: NSRunningApplication) {
        self.id = app.processIdentifier
        self.name = app.localizedName ?? "Unknown App"
        self.bundleIdentifier = app.bundleIdentifier
        self.icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
        self.processID = app.processIdentifier
    }

    // Hashable conformance (needed for Identifiable in some contexts)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.id == rhs.id
    }
}
