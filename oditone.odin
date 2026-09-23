package oditone

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:time"
import ma "vendor:miniaudio"

data_callback :: proc "c" (pDevice: ^ma.device, pOutput: rawptr, pInput: rawptr, frameCount: u32) {
	if pDevice == nil || pOutput == nil do return

	pSineWave := cast(^ma.waveform)pDevice.pUserData
	if pSineWave == nil do return

	// Safely fill buffer with waveform frames
	ma.waveform_read_pcm_frames(pSineWave, pOutput, u64(frameCount), nil)
}

parse_inputs :: proc(args: []string) -> (f64, time.Duration) {
	if len(args) == 3 {
		freq_val, freq_ok := strconv.parse_f64(args[1])
		sec_val, sec_ok := strconv.parse_int(args[2])
		if freq_ok && sec_ok {
			return freq_val, time.Duration(sec_val) * time.Second
		}
	}
	// Return default values
	return 440.0, time.Duration(2) * time.Second
}

main :: proc() {

	SAMPLE_RATE :: 44100 // Standard macOS sample rate
	CHANNELS :: 2

	freq, sec := parse_inputs(os.args)

	// 1. Explicit config struct initialization
	sine_config := ma.waveform_config {
		format     = .f32,
		channels   = u32(CHANNELS),
		type       = .sine,
		amplitude  = 0.2, // Keep below 1.0 to prevent clipping
		frequency  = freq,
		sampleRate = u32(SAMPLE_RATE),
	}

	sine_wave: ma.waveform
	if result := ma.waveform_init(&sine_config, &sine_wave); result != .SUCCESS {
		fmt.println("Waveform init failed:", result)
		return
	}
	defer ma.waveform_uninit(&sine_wave)

	// 2. Safe device config
	device_config := ma.device_config_init(.playback)
	device_config.playback.format = .f32
	device_config.playback.channels = u32(CHANNELS)
	device_config.sampleRate = u32(SAMPLE_RATE)
	device_config.dataCallback = data_callback
	device_config.pUserData = &sine_wave

	device: ma.device
	// Explicitly stop device before cleanup

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

	fmt.println("Playing tone...")
	time.sleep(sec)
	fmt.println("Stopping...")
}
