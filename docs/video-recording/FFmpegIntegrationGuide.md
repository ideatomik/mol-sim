# FFmpeg Integration Guide - Technical Details

This document provides the technical implementation details for integrating FFmpeg video encoding into Zymulador.

---

## FFmpeg Binary Acquisition

### Recommended Builds

**Windows (Primary Target)**
- Source: https://www.gyan.dev/ffmpeg/builds/
- Build type: `ffmpeg-release-essentials.zip` (smaller) or `ffmpeg-release-full.zip` (all codecs)
- License: LGPL (compatible with proprietary software when dynamically linked)
- Version requirement: 5.0 or later

**Alternative Windows Source**
- https://github.com/BtbN/FFmpeg-Builds/releases
- Choose: `ffmpeg-master-latest-win64-gpl-shared.zip` (if GPL acceptable)

**Linux**
- Prefer system FFmpeg via package manager
- Fallback: static build from https://johnvansickle.com/ffmpeg/

---

## Godot 4.x Process Management

### Using OSProcess for Pipe Communication

```gdscript
# ffmpeg_encoder.gd
class_name FFmpegEncoder
extends RefCounted

signal encoding_started
signal encoding_progress(percent: float)
signal encoding_completed(output_path: String)
signal encoding_failed(error: String)

var _process: OSProcess = null
var _width: int = 1920
var _height: int = 1080
var _fps: int = 30
var _codec: String = "libx264"
var _output_path: String = ""
var _frame_count: int = 0
var _total_expected_frames: int = 0

func start_encoding(p_output_path: String, p_width: int, p_height: int, 
                    p_fps: int, p_codec: String = "libx264") -> Error:
    _output_path = p_output_path
    _width = p_width
    _height = p_height
    _fps = p_fps
    _codec = p_codec
    _frame_count = 0
    
    var ffmpeg_path = _resolve_ffmpeg_path()
    if ffmpeg_path.is_empty():
        push_error("FFmpeg binary not found")
        return ERR_FILE_NOT_FOUND
    
    # Build FFmpeg command arguments
    # Reading rawvideo from stdin, outputting to file
    var args: PackedStringArray = [
        "-y",  # Overwrite output file
        "-f", "rawvideo",  # Input format
        "-pix_fmt", "bgra",  # Godot's Image format
        "-s", "%dx%d" % [p_width, p_height],  # Resolution
        "-r", str(p_fps),  # Framerate
        "-i", "-",  # Read from stdin
        "-c:v", p_codec,  # Video codec
    ]
    
    # Codec-specific options
    if p_codec == "libx264":
        args.append_array([
            "-preset", "medium",
            "-crf", "18",  # Quality: 0-51, lower=better, 18 is visually lossless
            "-pix_fmt", "yuv420p",  # Compatibility
            "-movflags", "+faststart"  # Web streaming optimization
        ])
    elif p_codec == "libvpx-vp9":
        args.append_array([
            "-b:v", "0",  # Variable bitrate
            "-crf", "30",  # Quality: 0-63
            "-pix_fmt", "yuv420p"
        ])
    
    args.append(p_output_path)
    
    # Spawn process
    _process = OSProcess.new()
    var err = _process.open(ffmpeg_path, args, true)  # true = redirect stdin
    
    if err != OK:
        push_error("Failed to start FFmpeg process: %d" % err)
        return err
    
    encoding_started.emit()
    return OK

func write_frame(image: Image) -> Error:
    if _process == null or not _process.is_open():
        return ERR_UNCONFIGURED
    
    # Convert Image to raw bytes (BGRA format)
    var data = image.data  # Returns PackedByteArray in BGRA order
    
    # Write to FFmpeg's stdin
    var written = _process.stdin.write(data)
    
    if written != data.size():
        push_error("Failed to write complete frame to FFmpeg")
        return ERR_CANT_WRITE
    
    _frame_count += 1
    
    # Emit progress if we know total frames
    if _total_expected_frames > 0:
        var percent = (_frame_count / float(_total_expected_frames)) * 100.0
        encoding_progress.emit(percent)
    
    return OK

func finish_encoding() -> void:
    if _process == null or not _process.is_open():
        return
    
    # Close stdin to signal EOF to FFmpeg
    _process.stdin.close()
    
    # Wait for process to complete (with timeout)
    var timeout = 60.0  # seconds
    var start_time = Time.get_ticks_msec() / 1000.0
    
    while _process.is_open():
        var current_time = Time.get_ticks_msec() / 1000.0
        if current_time - start_time > timeout:
            _process.kill()
            push_error("FFmpeg encoding timed out")
            encoding_failed.emit("Encoding timed out")
            return
        await get_tree().create_timer(0.1).timeout
    
    # Check exit code
    var exit_code = _process.get_exit_code()
    _process.close()
    _process = null
    
    if exit_code == 0:
        encoding_completed.emit(_output_path)
    else:
        push_error("FFmpeg exited with code %d" % exit_code)
        encoding_failed.emit("FFmpeg error (exit code %d)" % exit_code)

func set_expected_frame_count(count: int) -> void:
    _total_expected_frames = count

func _resolve_ffmpeg_path() -> String:
    # Check user override first
    if not ProjectSettings.has_setting("application/config/ffmpeg_path"):
        var override = ProjectSettings.get_setting("application/config/ffmpeg_path", "")
        if not override.is_empty() and FileAccess.file_exists(override):
            return override
    
    # Check bundled resources
    var bundled_path = ""
    if OS.get_name() == "Windows":
        bundled_path = "res://resources/ffmpeg/windows/ffmpeg.exe"
    elif OS.get_name() == "Linux":
        bundled_path = "res://resources/ffmpeg/linux/ffmpeg"
    
    if FileAccess.file_exists(bundled_path):
        return bundled_path
    
    # Try system PATH
    var system_path = "ffmpeg"  # Will use OS.find_binary() internally
    var test_process = OSProcess.new()
    var err = test_process.open(system_path, ["-version"])
    if err == OK:
        test_process.wait()
        test_process.close()
        return system_path
    
    return ""  # Not found anywhere
```

---

## Frame Capture Strategy

### Synchronous vs Asynchronous Capture

**Approach 1: Synchronous (Simpler, blocks rendering)**
```gdscript
# In VideoRecorderManager._process()
func _process(delta: float) -> void:
    if current_state != State.RECORDING:
        return
    
    _frame_timer += delta
    if _frame_timer >= _frame_interval:
        _frame_timer -= _frame_interval
        _capture_current_frame()

func _capture_current_frame() -> void:
    var viewport = get_viewport()
    var texture = viewport.get_texture()
    var image = texture.get_image()  # This can be slow!
    
    var err = _encoder.write_frame(image)
    if err != OK:
        push_error("Frame write failed: %d" % err)
        stop_recording()
```

**Approach 2: Asynchronous (Better performance, more complex)**
```gdscript
# Use a Thread to handle frame capture + encoding
var _capture_thread: Thread = null
var _frame_queue: ThreadSafeQueue = null

func _capture_current_frame_async() -> void:
    var viewport = get_viewport()
    var texture = viewport.get_texture()
    var image = texture.get_image()
    
    # Queue for thread processing
    _frame_queue.push(image)

func _encoding_thread_func() -> void:
    while _is_recording:
        var image = _frame_queue.pop()
        if image != null:
            _encoder.write_frame(image)
```

### Optimizing Frame Capture

**1. Downscale Before Encoding**
```gdscript
func _capture_and_downscale(target_width: int, target_height: int) -> Image:
    var viewport = get_viewport()
    var texture = viewport.get_texture()
    var full_res_image = texture.get_image()
    
    # Only downscale if needed
    if full_res_image.get_width() != target_width or \
       full_res_image.get_height() != target_height:
        full_res_image.resize(target_width, target_height)
    
    return full_res_image
```

**2. Selective Frame Capture (Skip Frames)**
```gdscript
# Capture every Nth frame for lower FPS output
var _frame_skip_counter: int = 0
var _frames_to_skip: int = 0  # 0 = capture every frame

func _should_capture_frame() -> bool:
    if _frames_to_skip == 0:
        return true
    
    _frame_skip_counter += 1
    if _frame_skip_counter > _frames_to_skip:
        _frame_skip_counter = 0
        return true
    return false
```

**3. Region of Interest Capture**
```gdscript
# Only capture a sub-region of the viewport
func _capture_region(rect: Rect2) -> Image:
    var viewport = get_viewport()
    var texture = viewport.get_texture()
    var full_image = texture.get_image()
    
    var cropped = full_image.get_region(rect)
    return cropped
```

---

## Memory Management

### Ring Buffer Implementation

```gdscript
# frame_capture_buffer.gd
class_name FrameCaptureBuffer
extends RefCounted

var _buffer: Array[Image] = []
var _max_size: int = 300  # ~10 seconds at 30fps
var _dropped_frame_count: int = 0
var _head_index: int = 0  # For circular buffer

func push_frame(image: Image) -> bool:
    if _buffer.size() >= _max_size:
        # Buffer full - drop oldest frame
        _buffer.pop_front()
        _dropped_frame_count += 1
        push_warning("Frame dropped - buffer full (total dropped: %d)" % _dropped_frame_count)
    
    _buffer.append(image)
    return true

func pop_frame() -> Image:
    if _buffer.is_empty():
        return null
    return _buffer.pop_front()

func is_full() -> bool:
    return _buffer.size() >= _max_size

func size() -> int:
    return _buffer.size()

func clear() -> void:
    _buffer.clear()
    _dropped_frame_count = 0
    _head_index = 0

func get_dropped_count() -> int:
    return _dropped_frame_count
```

---

## Audio Integration (Future)

### Recording System Audio

```gdscript
# Requires GDExtension or third-party plugin
# Example using hypothetical audio_capture.gdextension

var _audio_capture: AudioCapture = null

func start_audio_recording() -> Error:
    _audio_capture = AudioCapture.new()
    return _audio_capture.start_capture(sample_rate := 48000, channels := 2)

func get_audio_buffer() -> PackedFloat32Array:
    return _audio_capture.get_samples()

func merge_audio_with_video(video_path: String, audio_path: String, 
                            output_path: String) -> Error:
    var ffmpeg_path = _resolve_ffmpeg_path()
    var args = PackedStringArray([
        "-y",
        "-i", video_path,
        "-i", audio_path,
        "-c:v", "copy",  # Copy video stream without re-encoding
        "-c:a", "aac",   # Encode audio as AAC
        "-b:a", "192k",
        output_path
    ])
    
    var process = OSProcess.new()
    var err = process.open(ffmpeg_path, args)
    if err == OK:
        process.wait()
        process.close()
        return OK if process.get_exit_code() == 0 else ERR_FAILED
    return err
```

---

## Error Recovery Strategies

### Graceful Degradation on Crash

```gdscript
func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        if current_state == State.RECORDING:
            # Save buffered frames as image sequence before exiting
            _emergency_save_frames()
            get_tree().quit()

func _emergency_save_frames() -> void:
    var emergency_dir = "user://recordings/emergency_%s/" % Time.get_datetime_string()
    DirAccess.make_dir_recursive_absolute(emergency_dir)
    
    var frame_num = 0
    while _capture_buffer.size() > 0:
        var image = _capture_buffer.pop_frame()
        var path = "%s/frame_%05d.png" % [emergency_dir, frame_num]
        image.save_png(path)
        frame_num += 1
    
    push_warning("Emergency saved %d frames to %s" % [frame_num, emergency_dir])
    
    # Create batch script for user to encode later
    _create_recovery_batch_script(emergency_dir, frame_num)
```

### Disk Space Monitoring

```gdscript
func _check_disk_space() -> bool:
    var available_space = OS.get_static_memory()  # Best effort estimate
    var estimated_file_size = _get_estimated_output_size()
    
    # Require 2x estimated size as safety margin
    if available_space < estimated_file_size * 2:
        push_error("Insufficient disk space for recording")
        return false
    return true

func _get_estimated_output_size() -> int:
    # Rough estimate: ~5 MB per minute at 1080p30 with H.264
    var bytes_per_minute = 5 * 1024 * 1024
    var minutes_per_second = 1.0 / 60.0
    return int(bytes_per_minute * minutes_per_second * 60)  # Default 60 sec
```

---

## Testing Checklist

### Functional Tests
- [ ] Start/stop recording cycle completes successfully
- [ ] Output file plays in VLC media player
- [ ] Output file plays in Windows Media Player
- [ ] Output file plays in web browser (WebM format)
- [ ] Recording works during active simulation
- [ ] Recording works during camera movement
- [ ] Recording works with UI hidden
- [ ] Long recordings (>5 min) complete without crash

### Performance Tests
- [ ] FPS impact measured (<10% degradation target)
- [ ] Memory usage stable over time (no leaks)
- [ ] No frame drops at target framerate
- [ ] Encoding speed exceeds realtime (1.5x minimum)

### Edge Cases
- [ ] FFmpeg binary missing - shows helpful error
- [ ] Disk full during recording - graceful failure
- [ ] Application crash during recording - recovery possible
- [ ] Very high resolutions (4K) - validates or fails gracefully
- [ ] Very low framerates (1 fps) - works correctly
- [ ] Very high framerates (120 fps) - works correctly

---

## Troubleshooting

### Common Issues

**Issue: "FFmpeg binary not found"**
- Solution: Ensure `ffmpeg.exe` exists in `res://resources/ffmpeg/windows/`
- Alternative: Set `application/config/ffmpeg_path` in project settings

**Issue: "Failed to write complete frame"**
- Cause: FFmpeg process crashed or stdin pipe broken
- Solution: Check FFmpeg stderr output for codec errors

**Issue: Output video is corrupted/green**
- Cause: Pixel format mismatch
- Solution: Verify `-pix_fmt bgra` matches Godot's Image format

**Issue: Output video has wrong colors**
- Cause: BGRA vs RGBA confusion
- Solution: Godot uses BGRA; ensure FFmpeg expects `bgra` pixel format

**Issue: Recording causes severe FPS drop**
- Cause: Synchronous frame capture blocking render thread
- Solution: Implement async capture with Thread class

**Issue: Audio/video out of sync**
- Cause: Different capture rates for audio vs video
- Solution: Use timestamps; resample audio in post-process

---

## Performance Benchmarks (Expected)

| Resolution | Framerate | Codec | CPU Usage | Encoding Speed | File Size (per min) |
|------------|-----------|-------|-----------|----------------|---------------------|
| 1920x1080  | 30 fps    | H.264 | ~30%      | 2.5x realtime  | ~5 MB               |
| 1920x1080  | 60 fps    | H.264 | ~50%      | 1.8x realtime  | ~8 MB               |
| 3840x2160  | 30 fps    | H.264 | ~70%      | 1.2x realtime  | ~15 MB              |
| 1920x1080  | 30 fps    | VP9   | ~40%      | 1.5x realtime  | ~3 MB               |
| 1920x1080  | 30 fps    | ProRes| ~20%      | 5.0x realtime  | ~150 MB             |

*Benchmarks estimated for Intel i7-10700K, 32GB RAM, NVMe SSD*

---

## References

- FFmpeg Documentation: https://ffmpeg.org/documentation.html
- Godot 4.x OSProcess API: https://docs.godotengine.org/en/stable/classes/class_osprocess.html
- Godot 4.x Image Class: https://docs.godotengine.org/en/stable/classes/class_image.html
- libx264 Settings Guide: https://trac.ffmpeg.org/wiki/Encode/H.264
- VP9 Encoding Guide: https://trac.ffmpeg.org/wiki/Encode/VP9

---

*Document created: August 2026*
*Status: Technical reference for implementation*
