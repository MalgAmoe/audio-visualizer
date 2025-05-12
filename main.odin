package main

import "audio"
import "core:fmt"
import "core:mem"
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

	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .WINDOW_HIGHDPI, .MSAA_4X_HINT})
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "The Thing!")
	defer rl.CloseWindow()


	// set test signal frequency
	data.sine_osc.freq = 200

	// setup audio
	audio.init_stream(&data)
	defer audio.quit(&data)

	rl.SetTargetFPS(60)
	rl.HideCursor()

	width := f32(WINDOW_WIDTH)
	height := f32(WINDOW_HEIGHT)
	spacing := (f32(audio.SAMPLE_RATE) * 0.5) / f32(audio.ANALYSIS_BUFFERS / 4)

	clicked := false

	for !rl.WindowShouldClose() {
		width = f32(rl.GetScreenWidth())
		height = f32(rl.GetScreenHeight())
		check_inputs(&data)
		rms := data.rms
		wave_samples := data.buffer
		spectrum := data.spectrum

		rl.BeginDrawing()

		draw()
		rl.DrawText(fmt.ctprintf("rms: %f", rms), 10, 10, 20, rl.RAYWHITE)

		for i in 0 ..< len(wave_samples) / 2 - 1 {
			i_f := f32(i)
			x1 := (i_f / audio.ANALYSIS_BUFFERS) * width
			y1 := ((1.0 - wave_samples[i]) * (height * 0.5))
			x2 := ((i_f + 1) / audio.ANALYSIS_BUFFERS) * width
			y2 := ((1.0 - wave_samples[i + 1]) * (height * 0.5))

			rl.DrawLineEx({x1, y1}, {x2, y2}, 1, rl.RAYWHITE)
		}

		for i in 0 ..< len(spectrum) - 1 {
			i_f := f32(i)
			bins := f32(len(spectrum))

			x1 := (1 + (audio.calc_position(i_f * spacing))) * (width * 0.5)
			y1 := ((1 - 0.065 * (spectrum[i] + 10))) * height
			x2 := (1 + (audio.calc_position((i_f + 1) * spacing))) * (width * 0.5)
			y2 := ((1 - 0.065 * (spectrum[i + 1] + 10))) * height

			rl.DrawLine(i32(x1), i32(y1), i32(x2), i32(y2), rl.RAYWHITE)
		}

		rl.EndDrawing()
	}
}
