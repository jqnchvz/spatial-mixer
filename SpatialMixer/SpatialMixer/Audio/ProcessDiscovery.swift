//
//  ProcessDiscovery.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 09-02-26.
//

import AppKit
import Combine

/// Service to discover and monitor running macOS applications with audio capability
@MainActor
class ProcessDiscovery: ObservableObject {
    /// List of currently running apps (filtered)
    @Published var runningApps: [AppInfo] = []

    /// Filter to only show likely audio-capable apps
    @Published var filterAudioAppsOnly = true {
        didSet {
            discoverApps()
        }
    }

    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    init() {
        setupObservers()
        discoverApps()
    }

    deinit {
        // Remove observers synchronously (deinit is not actor-isolated)
        if let observer = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Discover all currently running applications
    func discoverApps() {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications

        // Filter for regular applications (not system processes)
        runningApps = apps
            .filter { shouldIncludeApp($0) }
            .map { AppInfo(from: $0) }
            .sorted { $0.name < $1.name }
    }

    /// Determine if an app should be included in the list
    private func shouldIncludeApp(_ app: NSRunningApplication) -> Bool {
        // Exclude background-only apps
        guard app.activationPolicy == .regular else {
            return false
        }

        // Must have a name
        guard let name = app.localizedName, !name.isEmpty else {
            return false
        }

        // Exclude Finder (it doesn't produce audio we want to capture)
        if app.bundleIdentifier == "com.apple.finder" {
            return false
        }

        // Exclude our own app
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return false
        }

        // If filtering for audio apps only, check if likely audio-capable
        if filterAudioAppsOnly {
            return isLikelyAudioCapable(app)
        }

        return true
    }

    /// Check if an app is likely to be audio-capable
    private func isLikelyAudioCapable(_ app: NSRunningApplication) -> Bool {
        guard let bundleID = app.bundleIdentifier else { return false }

        // Known audio-capable app patterns
        let audioAppPatterns = [
            // Browsers (YouTube, web audio, etc.)
            "safari",
            "chrome",
            "firefox",
            "edge",
            "brave",
            "arc",
            "opera",

            // Music & Media Players
            "music",
            "spotify",
            "itunes",
            "tv", // Apple TV
            "quicktime",
            "vlc",
            "iina",

            // Communication
            "facetime",
            "zoom",
            "teams",
            "slack",
            "discord",
            "skype",
            "webex",

            // Podcasts & Audio
            "podcasts",
            "overcast",
            "audible",
            "soundcloud",

            // Video & Streaming
            "netflix",
            "hulu",
            "youtube",
            "twitch",

            // Creative Apps
            "logic",
            "garageband",
            "ableton",
            "reaper",
            "audacity",
        ]

        let lowercaseID = bundleID.lowercased()
        return audioAppPatterns.contains { lowercaseID.contains($0) }
    }

    /// Set up notification observers for app launch/terminate
    private func setupObservers() {
        let workspace = NSWorkspace.shared

        // Observe app launches
        launchObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // Refresh the entire list to respect current filter setting
                self.discoverApps()
            }
        }

        // Observe app terminations
        terminateObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // Refresh the entire list to respect current filter setting
                self.discoverApps()
            }
        }
    }

    /// Remove notification observers
    private func removeObservers() {
        if let observer = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
