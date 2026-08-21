# Video Recording & Export System - Implementation Plan

## Overview

This document outlines the plan for implementing an in-engine video recording and export system for Zymulador, allowing users to record simulation footage directly to video files (MP4/WebM) without relying on external screen capture tools.

---

## Goals

1. **Direct video export** from the Godot 4.6 simulation
2. **High-quality output** suitable for educational content creation
3. **Minimal performance impact** during recording
4. **User-friendly workflow** integrated into existing UI
5. **Flexible configuration** (resolution, framerate, codec, quality)

---

## Technical Constraints & Considerations

### Godot 4.x Video Recording Capabilities

Godot 4.x does **NOT** have built-in video encoding/export functionality. We must choose one of these approaches:

#### Option A: FFmpeg Pipe Integration (RECOMMENDED)
- Capture frames via `Viewport.get_texture().get_image()`
- Stream raw frames to FFmpeg process via stdin pipe
- FFmpeg encodes to MP4/WebM in real-time or post-process
- **Pros**: Full codec control, industry-standard quality, no engine modification needed
- **Cons**: Requires FFmpeg binary bundled with application, platform-specific paths

#### Option B: Image Sequence Export
- Save individual PNG frames to disk during recording
- User runs separate FFmpeg command post-recording (or we provide a batch script)
- **Pros**: Simplest implementation, zero runtime dependency, lossless source
- **Cons**: Two-step workflow, large intermediate files, not "direct export"

#### Option C: Third-party Plugin
- Use existing Godot video recording plugins (e.g., `godot-video-recorder`)
- **Pros**: Pre-built solution
- **Cons**: Limited maintenance, may not support Godot 4.6, less control

#### Option D: Custom GDExtension Encoder
- Write C++ GDExtension using libx264/FFmpeg libraries
- **Pros**: Best performance, fully integrated
- **Cons**: Highest complexity, requires C++ expertise, build pipeline overhead

**Decision**: **Option A (FFmpeg Pipe)** for v1, with **Option B (Image Sequence)** as fallback mode.

---

## Architecture

### Component Breakdown

```
┌─────────────────────────────────────────────────────────────┐
│                     VideoRecorderManager                    │
│  (Singleton/Autoload - coordinates recording session)       │
├─────────────────────────────────────────────────────────────┤
│  - Recording state machine (IDLE → RECORDING → ENCODING)   │
│  - Frame capture timing & buffering                        │
│  - FFmpeg process lifecycle management                     │
│  - Configuration (resolution, fps, codec, bitrate)         │
│  - Progress tracking & error handling                      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   FrameCaptureBuffer                        │
│  (Ring buffer for frame queue during recording)             │
├─────────────────────────────────────────────────────────────┤
│  - Stores captured Image objects                           │
│  - Handles frame pacing vs. simulation speed               │
│  - Prevents memory overflow on long recordings             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    FFmpegEncoder                            │
│  (Wrapper for FFmpeg subprocess communication)              │
├─────────────────────────────────────────────────────────────┤
│  - Process spawning with platform-specific paths           │
│  -stdin pipe for raw frame streaming                       │
│  - Configurable codec presets (libx264, libvpx-vp9)        │
│  - Audio track merging (optional, post-process)            │
└─────────────────────────────────────────────────────────────┘
```

### File Structure

```
scripts/
├── core/
│   └── video_recorder_manager.gd          # Main coordinator (autoload)
│   └── frame_capture_buffer.gd            # Ring buffer implementation
│   └── ffmpeg_encoder.gd                  # FFmpeg process wrapper
scenes/
├── VideoRecordPopup.tscn                  # Recording dialog UI
├── VideoRecordPopup.gd                    # Popup controller
docs/
├── video-recording/
│   ├── VideoRecordingDesign.md            # This plan (expanded)
│   └── FFmpegIntegrationGuide.md          # Technical integration notes
resources/
└── ffmpeg/                                # Bundled FFmpeg binaries
    ├── windows/
    │   └── ffmpeg.exe
    └── linux/
        └── ffmpeg
```

---

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1)

#### 1.1 FFmpeg Binary Bundling
- [ ] Download static FFmpeg builds for Windows (primary target)
- [ ] Add to `resources/ffmpeg/windows/ffmpeg.exe`
- [ ] Configure `.gitignore` to exclude large binaries if needed
- [ ] Document version requirements (FFmpeg ≥ 4.4 recommended)

#### 1.2 FrameCaptureBuffer Class
```gdscript
# scripts/core/frame_capture_buffer.gd
class_name FrameCaptureBuffer
extends RefCounted

var _buffer: Array[Image] = []
var _max_size: int = 300  # ~10 sec at 30fps before blocking
var _dropped_frame_count: int = 0

func push_frame(image: Image) -> bool
func pop_frame() -> Image
func is_full() -> bool
func clear() -> void
```

#### 1.3 FFmpegEncoder Wrapper
```gdscript
# scripts/core/ffmpeg_encoder.gd
class_name FFmpegEncoder
extends RefCounted

signal encoding_started
signal encoding_progress(percent: float)
signal encoding_completed(output_path: String)
signal encoding_failed(error: String)

var _process: OSProcess
var _is_encoding: bool = false

func start_encoding(output_path: String, width: int, height: int, fps: int, codec: String) -> Error
func write_frame(image: Image) -> Error
func finish_encoding() -> void
func get_process_id() -> int
```

#### 1.4 VideoRecorderManager (Autoload)
```gdscript
# scripts/core/video_recorder_manager.gd
extends Node

enum State { IDLE, RECORDING, FINISHING }
enum QualityPreset { LOW, MEDIUM, HIGH, ULTRA }

signal recording_started
signal recording_stopped
signal export_completed(file_path: String)
signal export_failed(error: String)

@export var default_resolution: Vector2i = Vector2i(1920, 1080)
@export var default_fps: int = 30
@export var quality_preset: QualityPreset = QualityPreset.HIGH
@export var ffmpeg_path_override: String = ""  # For user-specified path

var current_state: State = State.IDLE
var _capture_buffer: FrameCaptureBuffer
var _encoder: FFmpegEncoder
var _frame_timer: float = 0.0
var _frame_interval: float = 1.0 / 30.0
var _output_directory: String = "user://recordings/"

func _process(delta: float)
func start_recording(config: Dictionary = {}) -> Error
func stop_recording() -> Error
func is_recording() -> bool
func get_recording_duration() -> float
func _capture_current_frame()
func _resolve_ffmpeg_path() -> String
```

---

### Phase 2: UI Integration (Week 2)

#### 2.1 VideoRecordPopup Scene
- Modal dialog with recording controls
- Resolution selector (720p, 1080p, 1440p, 4K, custom)
- Framerate selector (24, 30, 60 fps)
- Quality preset dropdown (affects bitrate)
- Output format selector (MP4, WebM)
- Output directory browser
- Recording timer display
- Start/Stop buttons with confirmation

#### 2.2 Integration Points
- Add "Record Video..." button to PlayerUI or main menu
- Keyboard shortcut (e.g., `Ctrl+R` or configurable)
- Recording indicator overlay (red dot + timer)
- Post-recording file browser option

#### 2.3 Localization
- Add strings to `ui_strings.csv`:
  - `video_record_title`
  - `video_record_resolution`
  - `video_record_framerate`
  - `video_record_quality`
  - `video_record_format`
  - `video_record_start`
  - `video_record_stop`
  - `video_record_exporting`
  - `video_record_success`
  - `video_record_ffmpeg_missing`

---

### Phase 3: Advanced Features (Week 3)

#### 3.1 Camera Path Recording
- Integrate with existing `camera_regent.gd` scripted shots
- Allow recording of multi-shot sequences
- Option to include/exclude UI overlays during recording

#### 3.2 Audio Track Support
- Capture system audio or microphone input
- Merge audio track with video in post-process FFmpeg pass
- Audio sync verification

#### 3.3 Performance Optimization
- Downscale capture resolution independently of render resolution
- Async frame encoding (separate thread via Thread class)
- Frame skip detection and compensation
- GPU readback optimization (avoid unnecessary conversions)

#### 3.4 Image Sequence Fallback Mode
```gdscript
func export_as_image_sequence(output_dir: String, prefix: String = "frame_") -> Error
# Saves PNG frames that user can encode later with:
# ffmpeg -framerate 30 -i frame_%04d.png -c:v libx264 -pix_fmt yuv420p output.mp4
```

---

## FFmpeg Command Templates

### H.264 MP4 (Maximum Compatibility)
```bash
ffmpeg -y -f rawvideo -pix_fmt bgra -s 1920x1080 -r 30 -i - \
  -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
  -movflags +faststart output.mp4
```

### VP9 WebM (Better Compression, Web-Friendly)
```bash
ffmpeg -y -f rawvideo -pix_fmt bgra -s 1920x1080 -r 30 -i - \
  -c:v libvpx-vp9 -b:v 0 -crf 30 -pix_fmt yuv420p \
  output.webm
```

### ProRes (Highest Quality, Large Files)
```bash
ffmpeg -y -f rawvideo -pix_fmt bgra -s 1920x1080 -r 30 -i - \
  -c:v prores_ks -profile:v 3 -vendor ap10 \
  output.mov
```

---

## Platform-Specific Considerations

### Windows (Primary Target)
- Bundle `ffmpeg.exe` as embedded resource or adjacent file
- Use `OS.create_process()` with full path
- Handle Windows Defender false positives (signed binary preferred)
- Default output: `%USERPROFILE%\Videos\Zymulador\`

### Linux (Secondary)
- Check system FFmpeg first (`which ffmpeg`)
- Fall back to bundled binary
- Default output: `$HOME/Videos/Zymulador/`

### macOS (Future)
- Not priority for initial release
- Same approach as Linux
- Codesigning requirements for distribution

---

## Error Handling & Edge Cases

| Scenario | Handling Strategy |
|----------|------------------|
| FFmpeg binary missing | Show error dialog with download link; offer image-sequence fallback |
| Disk full during recording | Stop recording gracefully; save partial video; warn user |
| Recording interrupted (crash) | Auto-save buffered frames as image sequence |
| Very long recording (>30 min) | Warn about file size; suggest splitting; enable chunking mode |
| Low FPS during recording | Drop frames gracefully; log warning; don't block simulation |
| Unsupported resolution | Validate against viewport capabilities; clamp to max |

---

## Testing Strategy

### Unit Tests
- `FrameCaptureBuffer`: push/pop semantics, overflow behavior
- `FFmpegEncoder`: process lifecycle, error codes
- Path resolution logic across platforms

### Integration Tests
- End-to-end recording session (start → capture → stop → encode)
- Verify output file plays correctly in VLC/mpv
- Test with various resolutions/framerates
- Test during active simulation (enzymes moving)
- Test with camera zoom/pan during recording

### Performance Benchmarks
- Measure FPS impact during recording (target: <10% degradation)
- Profile memory usage over 5-minute recording
- Benchmark encoding speed vs. realtime (should exceed 1x)

---

## Dependencies

### Required
- **FFmpeg** (static build, GPL or LGPL license compatible with project)
  - Recommended: https://www.gyan.dev/ffmpeg/builds/ (Windows)
  - Version: 5.0 or later for best codec support

### Optional
- **OBS Virtual Camera** (alternative capture method, not implemented initially)
- **NVENC/AMF hardware encoders** (future GPU-accelerated encoding)

---

## Licensing Considerations

- FFmpeg is typically GPL/LGPL licensed
- Static linking may require derivative work disclosure
- Dynamic invocation (subprocess) generally considered safe for proprietary software
- **Recommendation**: Use LGPL-build of FFmpeg, dynamically invoked via subprocess
- Include FFmpeg attribution in project credits/documentation

---

## Success Criteria

- [ ] User can record 60-second simulation clip at 1080p30 with single button press
- [ ] Output file plays in standard media players (VLC, Windows Media Player)
- [ ] Recording causes <10% FPS reduction on mid-range hardware
- [ ] No manual FFmpeg configuration required by end user
- [ ] Clear error messages when FFmpeg unavailable
- [ ] Localized UI strings in EN/ES/PT-BR
- [ ] Documentation in README and user manual

---

## Future Enhancements (Post-MVP)

1. **Animated GIF export** for short clips
2. **Live streaming** integration (Twitch/YouTube via RTMP)
3. **Built-in video editor** (trim, concatenate, add captions)
4. **One-click upload** to YouTube/Vimeo
5. **Hardware encoder support** (NVENC, AMF, QuickSync)
6. **Multi-camera angles** (simultaneous recording from different viewpoints)
7. **Chapter markers** from simulation events (enzyme firing, primer placement)

---

## Open Questions

1. Should we bundle FFmpeg (~100MB) or require user installation?
   - **Proposed**: Bundle minimal static build; allow override to system FFmpeg

2. Should recording pause the simulation, or run in real-time?
   - **Proposed**: Real-time by default; optional "turbo render" mode (uncapped FPS, then time-stretch)

3. Where should recorded videos be saved by default?
   - **Proposed**: Platform-standard video folder + subfolder `Zymulador/`

4. Should we support HDR/beyond-8-bit color?
   - **Proposed**: No for v1; standard Rec.709 8-bit sufficient for educational content

---

## Timeline Estimate

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| Phase 1: Core Infrastructure | 5-7 days | Working CLI recording, no UI |
| Phase 2: UI Integration | 5-7 days | User-facing recording dialog |
| Phase 3: Advanced Features | 7-10 days | Camera paths, audio, optimizations |
| Testing & Polish | 3-5 days | Bug fixes, localization, docs |
| **Total** | **20-29 days** | **Production-ready feature** |

---

## Next Steps

1. **Review this plan** with stakeholders
2. **Decide on FFmpeg bundling strategy** (bundle vs. require install)
3. **Set up development environment** with FFmpeg test binary
4. **Create GitHub issue** with Phase 1 tasks broken down
5. **Begin implementation** with `FrameCaptureBuffer` and `FFmpegEncoder` classes

---

*Document created: August 2026*
*Status: Planning phase - awaiting review*
