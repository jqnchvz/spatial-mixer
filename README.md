# SpatialMixer

A macOS menu bar application for controlling volume and spatial positioning of audio from different applications using spatial audio capabilities.

## Features (Planned)

- 🎚️ **Per-App Volume Control** - Independent volume control for each application
- 🎧 **Spatial Audio Positioning** - Position app audio in 3D space
- 🎯 **Multiple Spatial Modes** - Support for both pointSource (mono) and ambienceBed (stereo-preserving) modes
- 🖥️ **Menu Bar Integration** - Clean, native macOS menu bar interface
- 💾 **Persistent Settings** - Volume and position settings saved per application

## Requirements

- macOS 14.4 (Sonoma) or later
- AirPods Pro/Max recommended for optimal spatial audio experience
- Screen recording permission (required for Core Audio Taps)

## Technology Stack

- **Swift** & **SwiftUI** - Modern macOS app development
- **Core Audio Taps** - Per-application audio capture (macOS 14.4+)
- **AVAudioEngine** - Real-time audio processing
- **AVAudioEnvironmentNode** - 3D spatial audio rendering with HRTF

## Project Structure

```
SpatialMixer/
├── App/           # Main application entry point
├── Models/        # Data models and state management
├── Audio/         # Audio capture and processing
├── UI/            # SwiftUI views and components
└── Resources/     # Assets, icons, and resources
```

## Development Status

🚧 **In Development** - Following a structured 10-phase development plan:

1. ✅ Project Setup & Core Infrastructure
2. ⏳ Audio Permissions & Process Discovery
3. ⏳ Core Audio Capture (Core Audio Taps)
4. ⏳ AVAudioEngine Pipeline
5. ⏳ Spatial Audio Positioning
6. ⏳ Volume Control
7. ⏳ User Interface & Visualization
8. ⏳ Performance & Optimization
9. ⏳ Error Handling & Edge Cases
10. ⏳ Testing & Polish

## Building

1. Open `SpatialMixer.xcodeproj` in Xcode
2. Select the SpatialMixer scheme
3. Build and run (Cmd+R)

## License

TBD

## Acknowledgments

Built using native macOS frameworks and APIs:
- Core Audio Taps for per-app audio capture
- AVAudioEngine for spatial audio processing
- SwiftUI for modern UI development
