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

	rl.HideCursor()

	width := f32(WINDOW_WIDTH)
	height := f32(WINDOW_HEIGHT)


	clicked := false

	for !rl.WindowShouldClose() {
		width = f32(rl.GetScreenWidth())
		height = f32(rl.GetScreenHeight())

		check_inputs(&data)
		draw(&data, width, height)
	}
}
