package oditone

import "core:fmt"
import "core:math"
import ma "vendor:miniaudio"
import rl "vendor:raylib"

CHANNELS :: 2

Tone_Context :: struct {
	waveform: ma.waveform,
}

data_callback :: proc "c" (pDevice: ^ma.device, pOutput: rawptr, pInput: rawptr, frameCount: u32) {
	if pDevice == nil || pOutput == nil do return

	ctx := cast(^Tone_Context)pDevice.pUserData
	if ctx == nil do return

	ma.waveform_read_pcm_frames(&ctx.waveform, pOutput, u64(frameCount), nil)
}

// Map a normalized value [0.0, 1.0] to dynamic knob angle limits
get_knob_angle :: proc(value: f32, min_angle: f32 = -135.0, max_angle: f32 = 135.0) -> f32 {
	return min_angle + value * (max_angle - min_angle)
}

main :: proc() {
	SAMPLE_RATE :: 44100

	// 1. Initialize Raylib Window
	rl.InitWindow(800, 400, "Oditone")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	ctx: Tone_Context

	// Frequency limits
	MIN_FREQ :: 100.0
	MAX_FREQ :: 1000.0
	current_freq: f64 = 440.0

	// Knob parameters
	knob_center := rl.Vector2{400, 260}
	knob_radius: f32 = 70.0
	is_dragging := false
	drag_start_y: f32 = 0.0
	freq_at_drag_start: f64 = 440.0

	// 2. Configure Miniaudio Waveform
	sine_config := ma.waveform_config_init(
		.f32,
		u32(CHANNELS),
		u32(SAMPLE_RATE),
		.sine,
		0.2,
		current_freq,
	)

	if result := ma.waveform_init(&sine_config, &ctx.waveform); result != .SUCCESS {
		fmt.println("Waveform init failed:", result)
		return
	}
	defer ma.waveform_uninit(&ctx.waveform)

	// 3. Configure Output Device
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

	// 4. Main Event Loop
	for !rl.WindowShouldClose() {
		mouse_pos := rl.GetMousePosition()

		// Knob interaction: Start dragging on left-click within knob radius
		if rl.IsMouseButtonPressed(.LEFT) {
			if rl.CheckCollisionPointCircle(mouse_pos, knob_center, knob_radius) {
				is_dragging = true
				drag_start_y = mouse_pos.y
				freq_at_drag_start = current_freq
			}
		}

		if rl.IsMouseButtonReleased(.LEFT) {
			is_dragging = false
		}

		// Adjust frequency via vertical dragging (Audio plugin standard style)
		if is_dragging {
			delta_y := drag_start_y - mouse_pos.y // Move up to increase frequency
			sensitivity :: 2.0 // Hz per pixel dragged
			new_freq := freq_at_drag_start + f64(delta_y * sensitivity)
			current_freq = math.clamp(new_freq, MIN_FREQ, MAX_FREQ)
		}

		// Update miniaudio waveform frequency atomically
		ma.waveform_set_frequency(&ctx.waveform, current_freq)

		// Render UI
		rl.BeginDrawing()
		rl.ClearBackground(rl.DARKGRAY)

		rl.DrawText("Audio Control", 20, 20, 24, rl.RAYWHITE)
		rl.DrawText("Click and drag the knob UP/DOWN to turn", 20, 55, 16, rl.LIGHTGRAY)

		// Calculate visual knob angle
		normalized_val := f32((current_freq - MIN_FREQ) / (MAX_FREQ - MIN_FREQ))
		angle_deg := get_knob_angle(normalized_val)
		angle_rad := angle_deg * math.RAD_PER_DEG

		// Outer Ring Track
		rl.DrawCircleSector(knob_center, knob_radius + 12, -135, 135, 32, rl.GRAY)
		rl.DrawCircleSector(knob_center, knob_radius + 12, -135, angle_deg, 32, rl.GREEN)

		// Knob Body
		knob_color := rl.SKYBLUE if is_dragging else rl.LIGHTGRAY
		rl.DrawCircleV(knob_center, knob_radius, knob_color)
		rl.DrawCircleLines(i32(knob_center.x), i32(knob_center.y), knob_radius, rl.WHITE)

		// Knob Indicator Line (Rotates with frequency)
		indicator_len := knob_radius - 12.0
		indicator_end := rl.Vector2 {
			knob_center.x + indicator_len * math.sin(angle_rad),
			knob_center.y - indicator_len * math.cos(angle_rad),
		}
		rl.DrawLineEx(knob_center, indicator_end, 5.0, rl.DARKGRAY)

		// Digital Display
		rl.DrawText(
			rl.TextFormat("%.1f Hz", current_freq),
			i32(knob_center.x) - 60,
			i32(knob_center.y) + i32(knob_radius) + 30,
			28,
			rl.GREEN,
		)

		rl.EndDrawing()
	}
}
