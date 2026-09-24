package oditone

import "base:runtime"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:time"
import ma "vendor:miniaudio"

CHANNELS :: 2

Tone_Context :: struct {
	waveform:        ma.waveform,
	rendered_frames: u64,
	max_frames:      u64,
	is_finished:     bool,
}

data_callback :: proc "c" (pDevice: ^ma.device, pOutput: rawptr, pInput: rawptr, frameCount: u32) {
	context = runtime.default_context()

	if pDevice == nil || pOutput == nil do return

	ctx := cast(^Tone_Context)pDevice.pUserData
	if ctx == nil || ctx.is_finished {
		// Output silence if finished or invalid context
		out_slice := mem.slice_ptr(cast(^f32)pOutput, int(frameCount * CHANNELS))
		mem.zero_slice(out_slice)
		return
	}
	if rand.float32() >= 0.98 {
		ma.waveform_set_frequency(&ctx.waveform, rand.float64_range(82.41, 1_318.51))
	}
	frames_to_read := u64(frameCount)

	// Clamp frames if this batch exceeds total target duration
	if ctx.rendered_frames + frames_to_read >= ctx.max_frames {
		frames_to_read = ctx.max_frames - ctx.rendered_frames
		ctx.is_finished = true
	}

	if frames_to_read > 0 {
		ma.waveform_read_pcm_frames(&ctx.waveform, pOutput, frames_to_read, nil)
		ctx.rendered_frames += frames_to_read
	}

	// Zero out remaining frames in the buffer to prevent static/clicks
	if frames_to_read < u64(frameCount) {
		unwritten_frames := int(u64(frameCount) - frames_to_read)
		offset_samples := int(frames_to_read) * CHANNELS

		out_ptr := rawptr(uintptr(pOutput) + uintptr(offset_samples * size_of(f32)))
		remaining_slice := mem.slice_ptr(cast(^f32)out_ptr, unwritten_frames * CHANNELS)
		mem.zero_slice(remaining_slice)
	}
}

parse_inputs :: proc(args: []string) -> (f64, f64) {
	if len(args) == 3 {
		freq_val, freq_ok := strconv.parse_f64(args[1])
		sec_val, sec_ok := strconv.parse_f64(args[2])
		if freq_ok && sec_ok {
			return freq_val, sec_val
		}
	}
	return 440.0, 2.0
}

main :: proc() {
	SAMPLE_RATE :: 44100

	freq, duration_sec := parse_inputs(os.args)

	ctx: Tone_Context
	ctx.max_frames = u64(duration_sec * f64(SAMPLE_RATE))

	// 1. Configure Waveform Generator
	sine_config := ma.waveform_config {
		format     = .f32,
		channels   = u32(CHANNELS),
		type       = .sine,
		amplitude  = 0.2,
		frequency  = freq,
		sampleRate = u32(SAMPLE_RATE),
	}

	if result := ma.waveform_init(&sine_config, &ctx.waveform); result != .SUCCESS {
		fmt.println("Waveform init failed:", result)
		return
	}
	defer ma.waveform_uninit(&ctx.waveform)

	// 2. Configure Output Device
	device_config := ma.device_config_init(.playback)
	device_config.playback.format = .f32
	device_config.playback.channels = u32(CHANNELS)
	device_config.sampleRate = u32(SAMPLE_RATE)
	device_config.dataCallback = data_callback
	device_config.pUserData = &ctx

	device: ma.device
	if result := ma.device_init(nil, &device_config, &device); result != .SUCCESS {
		fmt.println("Device init failed:", result)
		return
	}
	defer ma.device_uninit(&device)
	defer ma.device_stop(&device)

	if result := ma.device_start(&device); result != .SUCCESS {
		fmt.println("Device start failed:", result)
		return
	}

	fmt.printf("Playing tone (%.2f Hz) for %.2f seconds...\n", freq, duration_sec)

	// Poll until the audio callback finishes tracking frame limit
	for !ctx.is_finished {
		time.sleep(10 * time.Millisecond)
	}

	fmt.println("Playback complete.")
}
