package main

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import "core:sys/posix"
import ma "vendor:miniaudio"
import rl "vendor:raylib"

PORT_NAME :: "/dev/cu.usbserial-0001"
CHANNELS :: 2
SAMPLE_RATE :: 44100

MIN_FREQ :: 100.0
MAX_FREQ :: 1000.0

Tone_Context :: struct {
	waveform: ma.waveform,
}

// Miniaudio realtime audio callback
data_callback :: proc "c" (pDevice: ^ma.device, pOutput: rawptr, pInput: rawptr, frameCount: u32) {
	if pDevice == nil || pOutput == nil do return

	ctx := cast(^Tone_Context)pDevice.pUserData
	if ctx == nil do return

	ma.waveform_read_pcm_frames(&ctx.waveform, pOutput, u64(frameCount), nil)
}

main :: proc() {
	// -------------------------------------------------------------
	// 1. Configure Non-blocking POSIX Serial Handle
	// -------------------------------------------------------------
	fd := posix.open(PORT_NAME, {.RDWR, .NOCTTY, .NONBLOCK})
	if fd >= 0 {
		options: posix.termios
		if posix.tcgetattr(fd, &options) == .OK {
			posix.cfsetispeed(&options, posix.speed_t(115200))
			posix.cfsetospeed(&options, posix.speed_t(115200))

			options.c_cflag += {.CREAD, .CLOCAL, .CS8}
			options.c_cflag -= {.PARENB, .CSTOPB}

			options.c_lflag -= {.ICANON, .ECHO, .ECHOE, .ISIG}
			options.c_iflag -= {.IXON, .IXOFF, .IXANY}
			options.c_oflag -= {.OPOST}

			options.c_cc[.VMIN] = 0
			options.c_cc[.VTIME] = 0

			posix.tcsetattr(fd, .TCSANOW, &options)
		}
	} else {
		fmt.printfln("Warning: Serial port %s not found. Running in UI-only mode.", PORT_NAME)
	}
	defer if fd >= 0 do posix.close(fd)

	// -------------------------------------------------------------
	// 2. Initialize Miniaudio Synthesis
	// -------------------------------------------------------------
	ctx: Tone_Context
	current_freq: f64 = 440.0

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

	// -------------------------------------------------------------
	// 3. Initialize Raylib Window
	// -------------------------------------------------------------
	rl.InitWindow(800, 600, "Oditone Synthesizer")
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()

	knob_center := rl.Vector2{400, 270}
	knob_radius := f32(110.0)

	is_dragging := false
	drag_start_y: f32 = 0.0
	freq_at_drag_start: f64 = 440.0

	buf: [128]byte
	line_buf: strings.Builder
	strings.builder_init(&line_buf)
	defer strings.builder_destroy(&line_buf)

	for !rl.WindowShouldClose() {
		// ---------------------------------------------------------
		// 4. Poll ESP32 Serial Input (if connected)
		// ---------------------------------------------------------
		if fd >= 0 {
			for {
				bytes_read := posix.read(fd, raw_data(&buf), len(buf))
				if bytes_read <= 0 do break

				for i in 0 ..< bytes_read {
					b := buf[i]

					if b == '\n' {
						line_str := strings.trim_space(strings.to_string(line_buf))

						if len(line_str) > 0 {
							if parsed, ok := strconv.parse_f64(line_str); ok {
								current_freq = math.clamp(parsed, MIN_FREQ, MAX_FREQ)
							}
						}

						strings.builder_reset(&line_buf)
					} else if b != '\r' {
						strings.write_byte(&line_buf, b)
					}
				}
			}
		}

		// ---------------------------------------------------------
		// 5. Handle UI Mouse Interaction
		// ---------------------------------------------------------
		mouse_pos := rl.GetMousePosition()

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

		if is_dragging {
			delta_y := drag_start_y - mouse_pos.y
			sensitivity :: 2.0
			new_freq := freq_at_drag_start + f64(delta_y * sensitivity)
			current_freq = math.clamp(new_freq, MIN_FREQ, MAX_FREQ)
		}

		// Atomic Miniaudio waveform update
		ma.waveform_set_frequency(&ctx.waveform, current_freq)

		// ---------------------------------------------------------
		// 6. Draw UI
		// ---------------------------------------------------------
		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{24, 28, 36, 255})

		normalized := f32((current_freq - MIN_FREQ) / (MAX_FREQ - MIN_FREQ))
		start_angle_deg := f32(225.0)
		end_angle_deg := f32(-45.0)
		current_angle_deg := start_angle_deg + normalized * (end_angle_deg - start_angle_deg)
		current_angle_rad := current_angle_deg * math.RAD_PER_DEG

		// Background Track & Progress Fill
		rl.DrawCircleSector(knob_center, knob_radius + 18, 135, 405, 60, rl.Color{40, 48, 62, 255})
		rl.DrawCircleSector(
			knob_center,
			knob_radius + 18,
			135,
			135 + (1 - normalized) * 270,
			60,
			rl.Color{0, 180, 216, 255},
		)

		// Knob Body
		body_color := rl.Color{55, 68, 90, 255} if is_dragging else rl.Color{32, 38, 50, 255}
		rl.DrawCircleV(knob_center, knob_radius, body_color)
		rl.DrawCircleV(knob_center, knob_radius - 8, rl.Color{45, 54, 70, 255})
		rl.DrawCircleLines(
			i32(knob_center.x),
			i32(knob_center.y),
			knob_radius,
			rl.Color{60, 72, 92, 255},
		)

		// Indicator Line
		indicator_start := rl.Vector2 {
			knob_center.x + math.cos(current_angle_rad) * (knob_radius - 50),
			knob_center.y - math.sin(current_angle_rad) * (knob_radius - 50),
		}
		indicator_end := rl.Vector2 {
			knob_center.x + math.cos(current_angle_rad) * (knob_radius - 10),
			knob_center.y - math.sin(current_angle_rad) * (knob_radius - 10),
		}
		rl.DrawLineEx(indicator_start, indicator_end, 6.0, rl.Color{0, 212, 255, 255})

		// Digital Display & Labels
		freq_text := fmt.ctprintf("%.1f Hz", current_freq)
		rl.DrawText(
			freq_text,
			i32(knob_center.x) - rl.MeasureText(freq_text, 36) / 2,
			i32(knob_center.y) + 160,
			36,
			rl.WHITE,
		)

		rl.EndDrawing()
	}
}
