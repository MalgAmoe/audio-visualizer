package main

import "audio"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import "core:thread"

import rl "vendor:raylib"

WINDOW_HEIGHT :: 820
WINDOW_WIDTH :: 1200

data := audio.Data {
	sine_osc    = audio.SineOsc_create(120),
	shared_ring = audio.Ring{},
}

check_inputs :: proc(data: ^audio.Data) {

}

draw :: proc() {
	rl.ClearBackground(rl.BLACK)
}

main :: proc() {
	thread.run_with_data(&data, audio.analyse_audio)

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				for _, entry in track.allocation_map {
					fmt.eprintf("%v leaked %v bytes\n", entry.location, entry.size)
				}
			}
			if len(track.bad_free_array) > 0 {
				for entry in track.bad_free_array {
					fmt.eprintf("%v bad free at %v\n", entry.location, entry.memory)
				}
			}
		}
	}

	// setup audio
	audio.init_stream(&data)
	defer audio.quit(&data)

	// Check for command-line arguments
	args := os.args[1:]

	if len(args) == 1 {
		if audio.load_wav_file(&data, args[0]) {
			fmt.println("Successfully loaded WAV file")

			audio.play_wav(&data)
		} else {
			fmt.println("Failed to load WAV file")
			return
		}
	} else {
		// No arguments provided
		fmt.println("No WAV file specified.")
		fmt.println("Usage: your_program [wav_filename]")
		return
	}

	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .WINDOW_HIGHDPI, .MSAA_4X_HINT})
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "The Thing!")
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()


	// set test signal frequency
	data.sine_osc.freq = 300


	rl.HideCursor()

	width := f32(WINDOW_WIDTH)
	height := f32(WINDOW_HEIGHT)


	clicked := false

	for !rl.WindowShouldClose() {
		width = f32(rl.GetScreenWidth())
		height = f32(rl.GetScreenHeight())
		check_inputs(&data)

		rl.BeginDrawing()

		draw()
		rl.DrawText(fmt.ctprintf("rms: %f", data.rms), 10, 10, 20, rl.RAYWHITE)

		for i in 0 ..< len(data.buffer) - 1 {
			i_f := f32(i)
			x1 := (i_f / audio.ANALYSIS_BUFFERS) * width * 0.5
			y1 := ((1.0 - data.buffer[i]) * (height * 0.5))
			x2 := ((i_f + 1) / audio.ANALYSIS_BUFFERS) * width * 0.5
			y2 := ((1.0 - data.buffer[i + 1]) * (height * 0.5))

			rl.DrawLineEx({x1, y1}, {x2, y2}, data.rms * 8, rl.RAYWHITE)
		}

		bins := len(data.spectrum)
		spacing := (f32(audio.SAMPLE_RATE) * 0.5) / f32(bins)

		for i in 0 ..< bins - 1 {
			// Calculate frequency of this bin and next bin
			freq1 := f32(i) * spacing
			freq2 := f32(i + 1) * spacing

			// Get normalized positions on log scale (0 to 1)
			pos1 := audio.calc_position(freq1)
			pos2 := audio.calc_position(freq2)

			// Convert to screen coordinates (use full width)
			x1 := (1 + pos1) * width * 0.5
			x2 := (1 + pos2) * width * 0.5

			// Normalize amplitude values - adjust these constants based on your actual spectrum values
			amplitude_min := f32(-12) // dB
			amplitude_max := f32(3) // dB

			// Clamp spectrum values and normalize to 0-1
			y_norm1 := math.clamp(
				(data.spectrum[i] - amplitude_min) / (amplitude_max - amplitude_min),
				0,
				1,
			)
			y_norm2 := math.clamp(
				(data.spectrum[i + 1] - amplitude_min) / (amplitude_max - amplitude_min),
				0,
				1,
			)

			// Convert to screen coordinates (0 at bottom, height at top)
			y1 := (1 - y_norm1) * height * 0.5
			y2 := (1 - y_norm2) * height * 0.5

			rl.DrawLine(i32(x1), i32(y1), i32(x2), i32(y2), rl.RAYWHITE)
		}

		rl.EndDrawing()
	}
}
