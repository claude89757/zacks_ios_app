# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

**Zacks Tennis** (Zacks 网球) - Intelligent tennis assistant iOS app with AI-powered video editing, court information, notifications, AI chat, and user profiles.

**Tech Stack**: SwiftUI + SwiftData (iOS 17+) · AVFoundation · Vision/CoreML · MVVM architecture

## Quick Start

### Open and Run

```bash
open zacks_tennis.xcodeproj  # Xcode 16.0+ required
# ⌘+B to build, ⌘+R to run, ⌘+U for tests
```

### Command Line Build

```bash
# List available simulators
xcrun simctl list devices available | grep "iPhone"

# Build with latest iPhone simulator (use any available iPhone from list above)
xcodebuild -project zacks_tennis.xcodeproj \
  -scheme zacks_tennis \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

## Architecture

### Project Structure

```
zacks_tennis/
├── zacks_tennisApp.swift    s   # App entry + SwiftData container
├── MainTabView.swift            # 4-tab navigation (Video is default)
├── Core/
│   ├── Models/                  # SwiftData @Model classes
│   │   ├── Video.swift          # Video metadata & analysis
│   │   ├── Court.swift, User.swift, NotificationItem.swift
│   └── Services/                # Singleton services (@MainActor, @Observable)
│       ├── VideoProcessingService.swift   # AVFoundation + Vision
│       ├── NetworkService.swift, NotificationService.swift
└── Features/                    # MVVM feature modules
    ├── VideoEditor/             # Primary feature (AI video editing)
    ├── CourtInfo/, AIChat/, Profile/, NotificationCenter/
```

### Tab Navigation

1. **场地** (Courts) - Court info + notifications (segmented control)
2. **视频** (Video) - AI video editing **[DEFAULT TAB]**
3. **ZACKS** (AI Chat) - Tennis assistant
4. **我的** (Profile) - User stats & settings

## Skills Available

### dev-docs-system

**Purpose**: Maintains focus and context during complex tasks by creating structured documentation in `docs/dev/active/[task-name]/`.

**Auto-creates three files**:

- `[task]-plan.md` - The accepted implementation plan (unchanging reference)
- `[task]-context.md` - Living document of decisions, key files, gotchas
- `[task]-tasks.md` - Checklist with iOS-specific quality checks

**When to use**:

- **Automatically**: When accepting plans with 3+ implementation steps
- **Automatically**: When user says "continue working on [task]"
- **Ask first**: For medium tasks (2-3 steps)
- iphone模拟设备 iphone 17