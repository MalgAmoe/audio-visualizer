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
OUTPUT_NUM_CHANNELS :: 2
BUFFER_SIZE :: 512
ANALYSIS_BUFFERS :: 8 * OUTPUT_NUM_CHANNELS * BUFFER_SIZE

window := hann_window(ANALYSIS_BUFFERS / 2)

Data :: struct {
	// test oscillator
	sine_osc:          SineOsc,

	// miniaudio
	device:            ma.device,

	// WAV file playback
	decoder:           ma.decoder,
	wav_loaded:        bool,
	is_playing:        bool,

	// audio analysis
	shared_ring:       Ring,
	rms:               f32,
	spectrum:          []f32,
	spectral_centroid: f32,
	buffer:            [ANALYSIS_BUFFERS]f32,
	mono_buffer:       [ANALYSIS_BUFFERS / 2]f32,
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

	if a.wav_loaded && a.is_playing {
		// Create a temporary buffer for decoded PCM frames
		temp_buffer: [BUFFER_SIZE * OUTPUT_NUM_CHANNELS]f32

		// Read the frames
		frames_read: u64
		result := ma.decoder_read_pcm_frames(
			&a.decoder,
			&temp_buffer[0],
			u64(frame_count),
			&frames_read,
		)

		if frames_read > 0 {
			// Copy frames to the output buffer
			for i in 0 ..< int(frames_read * OUTPUT_NUM_CHANNELS) {
				if i < buffer_size {
					device_buffer[i] = temp_buffer[i]
				}
			}

			// If we reached the end of the file and didn't fill the entire buffer
			if frames_read < u64(frame_count) {
				// Either stop playback or loop the file
				if true { 	// Set to false if you don't want looping
					ma.decoder_seek_to_pcm_frame(&a.decoder, 0) // Seek back to start for looping
				} else {
					a.is_playing = false
				}
			}
		} else {
			// No frames read, stop playback or restart
			a.is_playing = false
		}
	}

	// for i in 0 ..< frame_count {
	// 	sin_value := SineOsc_nextValue_linear(&a.sine_osc)

	// 	sample := 0.25 * sin_value
	// 	device_buffer[i * 2] = sample
	// 	device_buffer[i * 2 + 1] = sample
	// }

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

get_mono_analysis_buffer :: proc(buffer: []f32, mono_buffer: []f32) {
	for &sample, i in mono_buffer {
		sample = (buffer[2 * i] + buffer[2 * i + 1]) * 0.5
	}
}

analyse_audio :: proc(app_raw: rawptr) {
	app := (^Data)(app_raw)

	for {
		if (app.shared_ring.samples_added) {
			ring_read(&app.shared_ring, app.buffer[:])
			get_mono_analysis_buffer(app.buffer[:], app.mono_buffer[:])

			app.rms = calculate_rms(app.mono_buffer[:])

			windowed_buffer := app.mono_buffer * window
			fft_value := fft(windowed_buffer[:])
			app.spectrum = compute_spectrum(fft_value)
			app.spectral_centroid = spectral_centroid(app.spectrum)
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

load_wav_file :: proc(data: ^Data, filename: string) -> bool {
	// Clean up any existing decoder
	if data.wav_loaded {
		ma.decoder_uninit(&data.decoder)
		data.wav_loaded = false
	}

	// Initialize the decoder
	config := ma.decoder_config_init(ma.format.f32, OUTPUT_NUM_CHANNELS, SAMPLE_RATE)

	result := ma.decoder_init_file(fmt.ctprint(filename), &config, &data.decoder)
	if result != .SUCCESS {
		fmt.println("Failed to load WAV file:", filename)
		return false
	}

	data.wav_loaded = true
	return true
}

play_wav :: proc(data: ^Data) {
	if data.wav_loaded {
		// Reset to the beginning
		ma.decoder_seek_to_pcm_frame(&data.decoder, 0)
		data.is_playing = true
	}
}

stop_wav :: proc(data: ^Data) {
	data.is_playing = false
}

pause_wav :: proc(data: ^Data) {
	data.is_playing = false
}

resume_wav :: proc(data: ^Data) {
	if data.wav_loaded {
		data.is_playing = true
	}
}

quit :: proc(data: ^Data) {
	ma.device_stop(&data.device)
	ma.device_uninit(&data.device)
}
