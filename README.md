<p align="center">
  <img src="docs/logo.png" alt="Trails Logo" width="140" />
</p>

<h1 align="center">Trails</h1>

<p align="center">
  <strong>A Living Spatial Exploration Journal for iOS</strong><br>
  Architectural LiDAR mapping, 6DoF waypoint capture, dual-path retracing, and local-first memory preservation.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17.0%2B-black?style=flat-square&logo=apple" alt="iOS 17.0+" />
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat-square&logo=swift" alt="Swift 5.9" />
  <img src="https://img.shields.io/badge/LiDAR-RoomPlan-173E35?style=flat-square" alt="RoomPlan & LiDAR" />
  <img src="https://img.shields.io/badge/Architecture-Local--First%20Store-C66B4E?style=flat-square" alt="Local-First Store" />
  <img src="https://img.shields.io/badge/Design-Editorial%20Monograph-B59A58?style=flat-square" alt="Monograph Design System" />
</p>

---

## Overview

**Trails** is an Apple-native spatial computing application designed for handheld architectural survey, spatial memory recording, and historical space exploration. 

Built with **Apple RoomPlan**, **ARKit 6DoF LiDAR tracking**, and an organic editorial aesthetic, Trails bridges architectural precision with the contemplative luxury of an exhibition monograph. Creators record indoor journeys with continuous footstep vectors and multi-modal waypoints; followers retrace those paths with dynamic directional turn guidance, physical starting reference alignment, and live similarity scoring.

<p align="center">
  <img src="docs/stitch/v0.2.0/indoor_plan_dhun_haveli_ground_floor/screen.png" alt="Trails Indoor Blueprint" width="45%" />
  &nbsp;&nbsp;
  <img src="docs/stitch/v0.2.0/my_trails_spatial_journal/screen.png" alt="Trails Spatial Journal" width="45%" />
</p>

---

## Key Features

### 1. Spatial Recording with Live Architectural Blueprint
- **Simultaneous 6DoF Tracking & RoomPlan Meshing**: Captures walls, doors, windows, objects, and continuous footsteps without synthetic gamification.
- **Split-View Visualizer**: Upper pane displays the live LiDAR camera stream with depth cues; lower pane renders a real-time 2D architectural blueprint (`RoomLayoutView`).
- **Silent Starting Reference Frame**: Automatically captures the creator's initial vantage point and compass orientation at step zero to serve as the physical anchor for future followers.
- **Multi-Modal Waypoint Capture Dock**:
  - 🎥 **Spatial Video**: Full-screen recording anchored directly to 6DoF coordinates.
  - 📸 **High-Resolution Photo**: Rapid shutter capture with heading orientation metadata.
  - 🎙️ **Voice Notes**: In-situ audio memo recording with live waveform feedback.
  - 📝 **Field Notes**: Written architectural observations and reflections.
- **In-Capture Moments Tray**: Preview, caption, and curate recorded moments along the journey before finishing.

### 2. Dual-Path Retracing & Turn Navigation
- **Start of Trail Reference Vantage**: Displays the creator's exact starting photo and compass heading to guide the follower to the exact physical starting point.
- **Dual-Path Visual Encoding**:
  - **Original Reference Trail**: Rendered as a distinct purple dashed vector (`#9D7BD8`) with a purple `START` flag.
  - **Live Follower Walk**: Rendered in electric cyan (`#00E5FF`) with a dynamic position beacon and facing-heading cone.
- **Dynamic Directional Turn Guidance**:
  - Computes relative heading angles (`Ahead`, `Turn 90° Left/Right`, `Turn Around`).
  - Alerts the user when deviating off-trail (`X.Xm off trail · Steer toward purple path`).
  - Detects path bends ahead based on geometric curvature analysis.
- **Vantage Comparison & Checkpoint Arrival**:
  - Automatically alerts the user upon entering a checkpoint’s 3.5m spatial radius.
  - Side-by-side split sheet to inspect the creator's original vantage against the live view.
- **Live Similarity Index**:
  - Real-time scoring combining continuous path spatial coverage (within 3.5m) and visited checkpoint ratios.
- **First-Class Retraced Trails**:
  - When finished, retraced journeys are packaged and saved into the user's journal as new, independent recorded trails on their own merit, citing the original reference trail.

### 3. Local-First Spatial Packages (`.trail`)
- Completely offline, self-contained spatial archives containing `manifest.json`, footstep vectors, RoomPlan surface geometry, ARWorldMap relocalization data, and embedded media assets.
- Exportable, shareable, and zero-cloud reliant.

---

## System Architecture

```mermaid
flowchart TD
    subgraph Hardware ["Hardware & Sensors (iPhone Pro LiDAR)"]
        LiDAR["LiDAR Scanner & TrueDepth"]
        Camera["Ultra Wide / Wide RGB Camera"]
        IMU["IMU & CoreMotion (6DoF)"]
        Compass["CoreLocation Compass Heading"]
    end

    subgraph Perception ["Perception & Engine Layer"]
        ARKit["ARKit Session (ARWorldMap)"]
        RoomPlan["Apple RoomPlan Engine"]
        ScannerEng["RoomScannerEngine"]
        CameraEng["CameraCaptureEngine"]
        AudioEng["AudioManager (AVAudioRecorder)"]
        LocMgr["TrailsLocationManager"]
    end

    subgraph Storage ["Local-First Spatial Package Store (.trail)"]
        PackageStore["TrailPackageStore"]
        Manifest["manifest.json (TrailDetail)"]
        Footsteps["footsteps.json (SIMD3 Vectors)"]
        WorldMap["worldmap.arworldmap"]
        MediaDir["media/ (Photos, Videos, Audio)"]
    end

    subgraph UI ["Apple-Native Presentation Layer"]
        ScannerView["ScannerView (New Spatial Trail)"]
        RetraceView["RetraceTrailView (Retrace Companion)"]
        RoomLayout["RoomLayoutView (2D Blueprint)"]
        JournalView["TrailJournalDetailView (Monograph)"]
        DiscoverView["DiscoverView & Dhun Map"]
    end

    LiDAR --> ARKit
    Camera --> ARKit
    IMU --> ARKit
    Compass --> LocMgr

    ARKit --> RoomPlan
    RoomPlan --> ScannerEng
    ARKit --> ScannerEng
    Camera --> CameraEng
    LocMgr --> ScannerEng

    ScannerEng --> ScannerView
    CameraEng --> ScannerView
    AudioEng --> ScannerView
    ScannerEng --> RoomLayout

    ScannerView --> PackageStore
    PackageStore --> Manifest
    PackageStore --> Footsteps
    PackageStore --> WorldMap
    PackageStore --> MediaDir

    PackageStore --> RetraceView
    PackageStore --> JournalView
    PackageStore --> DiscoverView
    RetraceView --> RoomLayout
```

---

## Core Workflows

### 1. Spatial Recording Pipeline

```mermaid
sequenceDiagram
    autonumber
    actor Creator as Explorer
    participant Scanner as ScannerView
    participant Engine as RoomScannerEngine
    participant RoomPlan as Apple RoomPlan
    participant Store as TrailPackageStore

    Creator->>Scanner: Tap "Record"
    Scanner->>Engine: resetAndStartScanning()
    Engine->>Engine: Capture Silent Starting Frame & Orientation
    Engine->>RoomPlan: Stream 6DoF LiDAR Poses & Meshes
    loop Walking the Trail
        Engine->>Scanner: Stream Footstep Coordinates & Yaw
        Scanner->>Creator: Render Live 2D Blueprint (RoomLayoutView)
    end
    opt Capture Waypoint
        Creator->>Scanner: Tap Video / Photo / Voice / Note
        Scanner->>Store: Save media asset to active session
        Scanner->>Scanner: Append SpatialMoment to Ribbon
    end
    Creator->>Scanner: Tap "Finish"
    Scanner->>Store: finalizeAndSave() -> Compile .trail package
    Store-->>Creator: Trail Saved in Local Spatial Journal
```

---

### 2. Retrace & Relocalization State Machine

```mermaid
stateDiagram-v2
    [*] --> StartVantageGuidance: Launch Retrace Companion
    
    state StartVantageGuidance {
        [*] --> InspectReferencePhoto
        InspectReferencePhoto --> AlignCamera: Stand at Start & Face Heading
    }

    StartVantageGuidance --> RetracingActive: Tap "I'm Here · Begin Retrace"

    state RetracingActive {
        [*] --> TrackingOnTrail: Origin Synchronized
        TrackingOnTrail --> OffTrailSteering: Distance to Path > 4.5m
        OffTrailSteering --> TrackingOnTrail: Follow Directional Cue Back
        TrackingOnTrail --> ApproachingCheckpoint: Checkpoint Distance < 22m
        ApproachingCheckpoint --> CheckpointReached: Distance < 3.5m
        CheckpointReached --> VantageComparison: Tap "Compare Vantage"
        VantageComparison --> TrackingOnTrail: Mark Checkpoint Visited
        TrackingOnTrail --> CaptureNewMoment: Video / Photo / Mic / Note
        CaptureNewMoment --> TrackingOnTrail: Moment Anchored
    }

    RetracingActive --> CompleteJourney: Tap "Finish" or All Stops Visited
    CompleteJourney --> FirstClassTrailSaved: Save as New First-Class Trail
    FirstClassTrailSaved --> [*]
```

---

### 3. Dual-Path Visual Encoding & Similarity Scoring

```mermaid
flowchart LR
    subgraph ReferenceTrail ["Reference Trail (Purple #9D7BD8)"]
        RefPath["Continuous Dashed Vectors"]
        RefCheckpoints["Checkpoint Nodes (1..N)"]
        RefStart["START Flag Marker"]
    end

    subgraph RetraceTrail ["Follower Live Walk (Cyan #00E5FF)"]
        LivePath["Solid Walking Vector"]
        LiveBeacon["Current Position Beacon + Heading Cone"]
        NewMoments["New In-Situ Checkpoints"]
    end

    subgraph SimilarityEngine ["Similarity Index Engine"]
        PathCoverage["Path Coverage Ratio (Samples within 3.5m)"]
        StopCoverage["Checkpoint Coverage Ratio (Stops Visited)"]
        SimilarityFormula["Score = (Path Coverage × 50%) + (Stops Visited × 50%)"]
    end

    RefPath --> PathCoverage
    LivePath --> PathCoverage
    RefCheckpoints --> StopCoverage
    PathCoverage --> SimilarityFormula
    StopCoverage --> SimilarityFormula
```

---

## Design System & Editorial Palette

Trails is styled around **Modern Architectural Minimalism** combined with **Apple-native Tactility**. High-contrast mineral materials guarantee readability between bright ambient sunlight and dim architectural atriums.

| Material / Role | Hex Code | Visual Swatch | Purpose |
| :--- | :---: | :---: | :--- |
| **Limestone Canvas** | `#F5F1E8` | `rgb(245, 241, 232)` | Base paperboard background and floorplan ground |
| **Forest Green** | `#173E35` | `rgb(23, 62, 53)` | Structural chrome, primary CTA buttons, navigation accents |
| **Terracotta** | `#C66B4E` | `rgb(198, 107, 78)` | Active journey vector, active waypoints, primary recording |
| **Muted Brass** | `#B59A58` | `rgb(181, 154, 88)` | Checkpoint moment pins, compass arrows, architectural nodes |
| **Deep Ink** | `#202923` | `rgb(32, 41, 35)` | High-legibility editorial titles and primary typography |
| **Original Reference Path** | `#9D7BD8` | `rgb(157, 123, 216)` | Reference trail dashed vectors and start marker in Retrace |
| **Follower Retrace Path** | `#00E5FF` | `rgb(0, 229, 255)` | Live retrace vector, active navigation cues, match badge |

### Typography Hierarchy
- **Curatorial Editorial (`Newsreader`)**: Expressive, literary serif used for place monographs, space titles, and exhibition narrative reflections.
- **System Interface (`Inter`)**: Clean, ergonomic sans-serif for interactive sheets, buttons, list views, and HUD commands.
- **Survey Coordinates (`JetBrains Mono`)**: Strict, tabular monospace for LiDAR dimensions, coordinates, elevation offsets (`+14.2M`), compass headings (`45° NE`), and timer telemetry.

---

## Local Package Architecture (`.trail`)

Every trail in Trails is packaged as a completely self-contained folder structure:

```
<trailId>.trail/
├── manifest.json                  # TrailDetail metadata, author, place, moments array
├── footsteps.json                 # Array of SIMD3<Float> continuous 6DoF position vectors
├── spatial/
│   ├── worldmap.arworldmap        # Serialized ARKit ARWorldMap for coordinate relocalization
│   └── room_mesh.usdz             # 3D volumetric RoomPlan mesh
└── media/
    ├── start_frame.jpg            # Starting reference photo for retrace physical alignment
    ├── photo_<uuid>.jpg           # High-resolution checkpoint photos
    ├── video_<uuid>.mp4           # Spatial video recordings
    ├── thumb_<uuid>.jpg           # Video thumbnail previews
    └── voice_<uuid>.m4a           # AAC voice note observations
```

---

## Project Structure

```
trails/
├── docs/                          # Architecture PRDs, stitch design specs, brand assets
│   ├── prd/                       # Evolution PRDs (v0.1.0 through v0.4.0)
│   ├── stitch/                    # Design mockups, screen tokens, typography specs
│   └── logo.png                   # Official Trails brand mark
├── ios/                           # Native iOS Xcode Project & Swift Sources
│   ├── Sources/
│   │   ├── App/                   # App lifecycle (TrailsApp.swift), configurations
│   │   ├── Scanner/               # RoomPlan LiDAR engines, HUDs, camera & layout
│   │   │   ├── Managers/          # RoomScannerEngine, CameraCaptureEngine
│   │   │   └── Views/             # ScannerView, RoomLayoutView, FullScreenCapture
│   │   ├── Trails/                # Domain models, data stores, retrace flows
│   │   │   ├── Models/            # TrailModels, TrailsDataStore, ReferenceFrame
│   │   │   ├── Services/          # TrailPackageStore, AudioManager, LocationManager
│   │   │   └── Views/             # RetraceTrailView, TrailJournalDetailView, MyTrailsView
│   │   ├── TabBar/                # Main navigation (My Trails, Discover, Record, You)
│   │   └── UI/                    # AppColors, AppFonts, Haptics, common components
│   └── Trails.xcodeproj           # Xcode project definition
├── scripts/                       # Device deployment & runner automation (Bun/TypeScript)
│   └── ios-device.ts              # Command-line device detection, install, and logs
├── justfile                       # Project task runner
└── Taskfile.yml                   # Task runner configuration
```

---

## Getting Started

### Prerequisites
- **Hardware**: Mac running macOS Sonoma or Sequoia with Xcode 15+ / 16+.
- **Target Device**: iPhone 12 Pro or newer with LiDAR Scanner (iPhone 12/13/14/15/16 Pro or Pro Max).
- **Tooling**:
  - [Just](https://github.com/casey/just) command runner (`brew install just`)
  - [Bun](https://bun.sh) runtime (`brew install oven-sh/bun/bun`)

### Quick Commands

```bash
# List connected physical iOS devices
just ios-devices

# Build and deploy to your connected physical iPhone
just ios

# Non-waiting install handoff (ideal for background agent loops)
just ios-agent

# Build and run UI test suite
just ios-test

# Launch on iOS Simulator
just ios-simulator simulator="iPhone 15 Pro"

# Open directly in Xcode
just ios-open
```

### Environment Configuration (`.env`)
Create a `.env` file in the repo root to set your target device:

```env
IOS_DEVICE=00008101-001224822130001E
IOS_CONFIGURATION=Debug
IOS_DERIVED_DATA=build/ios/DerivedData
IOS_SOURCE_PACKAGES_DIR=build/ios/DerivedData/SourcePackages
IOS_RESET_SOURCE_PACKAGES=false
```

---

## PRD Evolution Milestones

- **v0.1.0 — Core Spatial Capture**: Initial RoomPlan LiDAR scan integration, basic step tracking, and local JSON persistence.
- **v0.2.0 — A Living Spatial Journal**: Introduced the monograph editorial aesthetic (Limestone, Terracotta, Forest Green), multi-level architectural floor filtering, and places taxonomy.
- **v0.2.1 — Waypoint Capture Dock & In-Situ Curating**: Added full-screen spatial video, photos, audio memos, and the interactive moments tray dock.
- **v0.3.0 & v0.3.1 — Reliable Reference Frames & Dual-Path Retrace**: Solved small-space coordinate drift through silent initial reference frame capture, physical starting vantage guidance, real-time directional turn cues, and similarity index scoring.
- **v0.4.0 — First-Class Retraces & Discover Catalogue**: Elevated retraced trails into independent first-class journal entries, added author attribution, and introduced community place discovery.

---

<p align="center">
  Crafted with care for architects, historians, spatial thinkers, and curious explorers.
</p>
