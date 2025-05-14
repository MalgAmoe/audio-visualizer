package audio

import "base:runtime"
import c "core:c/libc"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:sync"
import "core:time"

import ma "vendor:miniaudio"

SAMPLE_RATE: c.uint = 44100
OUTPUT_NUM_CHANNELS :: 1
BUFFER_SIZE :: 512
ANALYSIS_BUFFERS :: 4 * OUTPUT_NUM_CHANNELS * BUFFER_SIZE

window := hann_window(ANALYSIS_BUFFERS)

Data :: struct {
	// test oscillator
	sine_osc:    SineOsc,

	// miniaudio
	device:      ma.device,

	// audio analysis
	shared_ring: Ring,
	rms:         f32,
	spectrum:    []f32,
	buffer:      [ANALYSIS_BUFFERS]f32,
}

Ring :: struct {
	data:          [ANALYSIS_BUFFERS]f32,
	write_head:    int,
	samples_added: bool,
	mutex:         sync.Mutex,
}

audio_callback :: proc "c" (device: ^ma.device, output: rawptr, _input: rawptr, frame_count: u32) {
	context = runtime.default_context()
	a := (^Data)(device.pUserData)

	buffer_size := int(frame_count * OUTPUT_NUM_CHANNELS)
	device_buffer := mem.slice_ptr((^f32)(output), buffer_size)

	for i in 0 ..< frame_count {
		sin_value := SineOsc_nextValue_linear(&a.sine_osc)

		sample := 0.25 * sin_value
		device_buffer[i] =  /* * 2 */sample
		// device_buffer[i * 2 + 1] = sample
	}

	ring_write(&a.shared_ring, device_buffer[:])
}

ring_write :: proc(ring: ^Ring, audio_data: []f32) {
	sync.lock(&ring.mutex)
	defer sync.unlock(&ring.mutex)

	for i in 0 ..< len(audio_data) {
		current_write_head := (ring.write_head + i) % ANALYSIS_BUFFERS
		ring.data[current_write_head] = audio_data[i]
	}
	ring.write_head = (ring.write_head + len(audio_data)) % ANALYSIS_BUFFERS
	ring.samples_added = true
}

ring_read :: proc(ring: ^Ring, all_buffer: []f32) {
	sync.lock(&ring.mutex)
	defer sync.unlock(&ring.mutex)

	for &sample, i in all_buffer {
		sample = ring.data[(ring.write_head + i) % ANALYSIS_BUFFERS]
	}
	ring.samples_added = false
}

analyse_audio :: proc(app_raw: rawptr) {
	app := (^Data)(app_raw)

	for {
		if (app.shared_ring.samples_added) {
			ring_read(&app.shared_ring, app.buffer[:])

			app.rms = calculate_rms(app.buffer)

			windowed_buffer := app.buffer * window
			fft_value := fft(windowed_buffer[:])
			app.spectrum = compute_spectrum(fft_value)
		}

		time.accurate_sleep(10 * time.Millisecond)
	}
}

init_stream :: proc(data: ^Data) {
	device_config := ma.device_config_init(ma.device_type.playback)
	device_config.playback.channels = OUTPUT_NUM_CHANNELS
	device_config.playback.format = ma.format.f32
	device_config.sampleRate = SAMPLE_RATE
	device_config.dataCallback = ma.device_data_proc(audio_callback)
	device_config.periodSizeInFrames = BUFFER_SIZE
	device_config.pUserData = data

	engine_init_result := ma.device_init(nil, &device_config, &data.device)

	if (ma.device_start(&data.device) != .SUCCESS) {
		fmt.println("Failed to start playback device.")
		ma.device_uninit(&data.device)
		return
	}
}

quit :: proc(data: ^Data) {
	ma.device_stop(&data.device)
	ma.device_uninit(&data.device)
}
