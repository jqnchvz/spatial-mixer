# SpatialMixer - Claude Code Project Guide

## Project Overview

SpatialMixer is a macOS menu bar application that enables per-application volume control and 3D spatial audio positioning. This tool addresses the gap in macOS's native audio capabilities by providing users with fine-grained control over app audio positioning in 3D space using spatial audio technology.

**Repository:** https://github.com/jqnchvz/spatial-mixer
**Jira Project:** SPAT (https://comolagente.atlassian.net/jira/software/projects/SPAT/board)

## Development Workflow

### Task Management with Jira

This project follows a structured task-based workflow using Jira. **Always follow these steps:**

#### 1. Finding Your Next Task

1. Visit the Jira board: https://comolagente.atlassian.net/jira/software/projects/SPAT/board
2. Look for tasks in the "To Do" column
3. Start with the lowest numbered task (SPAT-11, SPAT-12, etc.) unless directed otherwise
4. Each task is linked to its parent Epic for context

**Jira Search Example:**
```
Use the Atlassian MCP plugin to search for tasks:
- Status: "To Do"
- Sort by: Issue Key (ascending)
- Project: SPAT
```

#### 2. Reading Task Details

Before starting work, **thoroughly read the task description** in Jira. Each task includes:

- **Acceptance Criteria** - What defines "done"
- **Implementation Steps** - Step-by-step guidance
- **Claude Code Prompt** - A ready-to-use prompt for implementation
- **Code Examples** - Reference implementations
- **Testing Guidelines** - How to verify it works
- **Parent Epic** - Context about which phase this belongs to

#### 3. Starting Work

When you begin a task:

1. **Transition to "In Progress"** in Jira
2. **Use the Claude Code Prompt** from the task description - it's specifically designed for that task
3. **Create a feature branch** following the naming convention: `feature/SPAT-XX-brief-description`

**Example:**
```bash
git checkout -b feature/SPAT-12-menubar-extra
```

#### 4. During Development

- Follow the implementation steps in the task description
- Write clean, well-documented code
- Test thoroughly according to the testing guidelines
- Make commits with clear, descriptive messages referencing the task (e.g., "SPAT-12: Implement MenuBarExtra lifecycle")

#### 5. Creating a Pull Request

When the task is complete:

1. **Push your branch** to GitHub
2. **Create a Pull Request** with:
   - Title format: `[SPAT-XX] Brief description`
   - Description including: What was implemented, testing done, any notes
   - Link to the Jira task
3. **Transition the task to "In Review"** in Jira
4. **Add a comment** to the Jira task with the PR link

**GitHub PR Command Example:**
```bash
gh pr create --title "[SPAT-12] Configure MenuBarExtra lifecycle" \
  --body "Implements SPAT-12: MenuBarExtra setup

## Changes
- Converted WindowGroup to MenuBarExtra
- Added menu bar icon
- Created MenuBarView with placeholder content

## Testing
- ✅ Menu bar icon appears
- ✅ Clicking shows menu content
- ✅ Works in light and dark mode

Jira: https://comolagente.atlassian.net/browse/SPAT-12"
```

#### 6. After PR Merge

When the PR is merged:

1. **Transition the task to "Done"** in Jira
2. **Delete the feature branch** (locally and remotely)
3. **Update your local main branch**
4. **Move to the next logical task** (usually the next sequential SPAT-XX number)

**Example:**
```bash
git checkout main
git pull origin main
git branch -d feature/SPAT-12-menubar-extra
gh pr list --state merged --limit 1  # Verify merge
```

## Technical Guidelines

### Architecture & Structure

The project follows a clean, modular architecture:

```
SpatialMixer/
├── App/           # Application lifecycle and entry point
├── Models/        # Data models, state management
├── Audio/         # Core Audio Taps, AVAudioEngine, spatial processing
├── UI/            # SwiftUI views, menu bar interface
└── Resources/     # Assets, icons, configurations
```

**Architectural Principles:**
- Separation of concerns: Audio processing separate from UI
- ObservableObject for state management
- Single responsibility for each class/component
- Dependency injection for testability

### Technology Stack

**Core Technologies:**
- **Swift 5.10+** - Modern Swift with async/await
- **SwiftUI** - Declarative UI framework for macOS
- **Core Audio Taps** - Per-app audio capture (macOS 14.4+)
- **AVAudioEngine** - Real-time audio processing pipeline
- **AVAudioEnvironmentNode** - 3D spatial audio with HRTF rendering
- **AppKit** - Menu bar integration (NSWorkspace, MenuBarExtra)

**Minimum Requirements:**
- macOS 14.4 (Sonoma) or later
- Xcode 15.3+
- Screen recording permission (for Core Audio Taps)

### Coding Standards

**Swift Style:**
- Follow Apple's Swift API Design Guidelines
- Use meaningful variable names (avoid abbreviations)
- Prefer `let` over `var` when possible
- Use `guard` for early returns
- Document public APIs with `///` comments

**SwiftUI Best Practices:**
- Keep views small and focused
- Extract reusable components
- Use `@StateObject` for ownership, `@ObservedObject` for passing
- Leverage `@Published` for reactive state updates
- Use proper view modifiers order (frame before padding, etc.)

**Audio Processing:**
- Never block the audio thread (real-time thread safety)
- Use lock-free data structures in audio callbacks
- Minimize allocations in audio processing code
- Proper format conversion between taps and engine
- Clean up audio resources (detach nodes, stop engine)

**Error Handling:**
- Use `Result<Success, Failure>` for operations that can fail
- Provide user-friendly error messages
- Log errors with context (file, function, line)
- Graceful degradation when features unavailable

### Permissions & Entitlements

This app requires specific permissions and entitlements:

**Info.plist:**
- `LSUIElement` = YES (hide from Dock)
- `NSMicrophoneUsageDescription` - Clear explanation of audio access need

**Entitlements:**
- `com.apple.security.device.audio-input` - For Core Audio Taps
- Screen recording permission requested at runtime

**Permission Flow:**
1. Check permission status on launch
2. Request if not granted
3. Show helpful UI explaining why needed
4. Provide "Open System Settings" button if denied

### Testing Strategy

**Manual Testing:**
- Test with real audio apps (Spotify, Safari, Apple Music)
- Verify spatial positioning with AirPods Pro/Max
- Test edge cases (app crashes, device disconnection)
- Verify performance with 5+ simultaneous sources

**Verification Checklist:**
- Build succeeds with no warnings
- App launches without Dock icon
- Menu bar icon appears correctly
- All features work as described in acceptance criteria
- No memory leaks (verify with Instruments)
- CPU usage acceptable (< 10% with 5 sources)

### Git Workflow

**Branch Strategy:**
- `main` - Production-ready code
- `feature/SPAT-XX-description` - Feature branches for each task

**Commit Messages:**
```
SPAT-XX: Brief description of what changed

- Detailed point 1
- Detailed point 2
- Testing notes

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**PR Requirements:**
- All code compiles without warnings
- Task acceptance criteria met
- Testing completed and documented
- Jira task transitioned to "In Review"

## Development Phases

The project follows a 10-phase development plan. Each phase builds on the previous:

### Phase 1: Project Setup & Core Infrastructure (SPAT-1)
✅ **Status:** Complete
Initial Xcode project, folder structure, basic menu bar app

### Phase 2: Audio Permissions & Process Discovery (SPAT-2)
⏳ **Status:** Pending
Screen recording permission flow, enumerate running apps

### Phase 3: Core Audio Capture (SPAT-3)
⏳ **Status:** Pending
Core Audio Taps implementation, per-app audio capture

### Phase 4: AVAudioEngine Pipeline (SPAT-4)
⏳ **Status:** Pending
Audio engine setup, node connections, format conversion

### Phase 5: Spatial Audio Positioning (SPAT-5)
⏳ **Status:** Pending
3D positioning with AVAudioEnvironmentNode, HRTF rendering

### Phase 6: Volume Control (SPAT-6)
⏳ **Status:** Pending
Per-app volume sliders, mute functionality, persistence

### Phase 7: User Interface & Visualization (SPAT-7)
⏳ **Status:** Pending
Spatial visualizer, position controls, polished menu bar UI

### Phase 8: Performance & Optimization (SPAT-8)
⏳ **Status:** Pending
Latency optimization, source activation, UI throttling

### Phase 9: Error Handling & Edge Cases (SPAT-9)
⏳ **Status:** Pending
Robust error handling, device changes, app lifecycle

### Phase 10: Testing & Polish (SPAT-10)
⏳ **Status:** Pending
Comprehensive testing, final polish, release preparation

## Key Technical Decisions

### Why Core Audio Taps?
Core Audio Taps (macOS 14.4+) provide the only native way to capture audio from specific applications without system extensions or hacks. This ensures:
- First-class API support from Apple
- Proper permission flow
- Low latency audio capture
- No system extension complexity

### Why AVAudioEnvironmentNode?
For spatial audio positioning, AVAudioEnvironmentNode provides:
- HRTF rendering for realistic 3D audio
- Support for both mono (pointSource) and stereo (ambienceBed) modes
- Automatic adaptation to output device capabilities
- Integration with AVAudioEngine pipeline

### Spatial Mode Strategy
Default to `ambienceBed` mode for most apps to preserve stereo information:
- Music apps (Spotify, Apple Music) → ambienceBed (preserves stereo width)
- Video apps (YouTube, Safari) → ambienceBed
- Games / Sound effects → pointSource (precise positioning)

Users can override per-app via UI settings.

## Common Tasks

### Adding a New Model
1. Create file in `Models/` directory
2. Implement `ObservableObject` if it holds mutable state
3. Use `@Published` for properties that trigger UI updates
4. Document public interface with `///` comments

### Adding a New UI View
1. Create file in `UI/` directory
2. Keep views small and focused (< 100 lines when possible)
3. Extract subviews for reusability
4. Preview using `#Preview` macro
5. Test in both light and dark mode

### Adding Audio Processing
1. Create file in `Audio/` directory
2. Never block the audio thread
3. Use proper format conversion
4. Clean up resources in deinit
5. Test with multiple simultaneous sources

## Troubleshooting

### Permission Issues
If Core Audio Taps fail:
1. Verify screen recording permission granted
2. Check System Settings → Privacy & Security → Screen Recording
3. Restart app after granting permission

### Audio Glitches
If audio stutters or drops:
1. Check buffer sizes (balance latency vs stability)
2. Profile with Instruments (Time Profiler)
3. Verify no blocking operations in audio callbacks
4. Check CPU usage in Activity Monitor

### Xcode Build Issues
If build fails:
1. Clean build folder (Cmd+Shift+K)
2. Clear DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData`
3. Verify deployment target is macOS 14.4+
4. Check all files are in correct target

## Resources

**Apple Documentation:**
- [Core Audio Taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)
- [AVAudioEnvironmentNode](https://developer.apple.com/documentation/avfaudio/avaudioenvironmentnode)
- [MenuBarExtra](https://developer.apple.com/documentation/SwiftUI/Building-and-customizing-the-menu-bar-with-SwiftUI)
- [WWDC 2019 - AVAudioEngine](https://developer.apple.com/videos/play/wwdc2019/510/)

**Reference Implementations:**
- [AudioCap](https://github.com/insidegui/AudioCap) - Core Audio Taps example
- [FineTune](https://github.com/ronitsingh10/FineTune) - Per-app volume control

**Jira Board:**
- [SPAT Project Board](https://comolagente.atlassian.net/jira/software/projects/SPAT/board)

## Notes for Claude Code

When working on this project:

1. **Always check Jira first** - Use the Atlassian MCP plugin to find the next task
2. **Read the full task description** - Contains crucial context and implementation guidance
3. **Use the Claude Code Prompt** - Each task has a tailored prompt for you
4. **Update Jira status** - Transition tasks as you progress through the workflow
5. **Reference task numbers** - Always include SPAT-XX in commits, PRs, and comments
6. **Test thoroughly** - Follow the testing guidelines in each task
7. **Provide insights** - Share educational context about implementation decisions
8. **Ask when uncertain** - Use AskUserQuestion if requirements are unclear

This is a learning project that demonstrates advanced macOS audio programming, spatial audio concepts, and modern SwiftUI development. Take time to explain architectural decisions and technical choices.
