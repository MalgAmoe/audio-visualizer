package main

import "core:fmt"
import "core:mem"
import vmem "core:mem/virtual"
import "core:os"
import "core:thread"
import rl "vendor:raylib"

import "audio"

WINDOW_HEIGHT :: 820
WINDOW_WIDTH :: 1200

check_inputs :: proc(data: ^audio.Data) {

}

analysis_thread :: proc(t: ^thread.Thread) {
	data := cast(^audio.Data)t.data
	audio.analyse_audio(data)
}

main :: proc() {
	// setup tracking allocator for memory leaks
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

	// set arena for audio data struct
	memory_arena: vmem.Arena
	arena_allocator := vmem.arena_allocator(&memory_arena)
	defer vmem.arena_destroy(&memory_arena)

	// create audio data
	data := new(audio.Data, arena_allocator)

	// setup analysis thread
	thread_handle := thread.create(analysis_thread)
	thread_handle.data = rawptr(data)
	thread.start(thread_handle)
	data.run_analyis = true
	defer {
		data.run_analyis = false
		thread.join(thread_handle)
		thread.destroy(thread_handle)
	}

	// setup audio
	audio.init_stream(data)
	defer audio.quit(data)

	// Check for command-line arguments
	args := os.args[1:]
	if len(args) == 1 {
		if audio.load_wav_file(data, args[0]) {
			fmt.println("Successfully loaded WAV file")

			audio.play_wav(data)
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

	// setup raylib
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .WINDOW_HIGHDPI, .MSAA_4X_HINT})
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Audio Thingy")
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()

	rl.HideCursor()

	width := f32(WINDOW_WIDTH)
	height := f32(WINDOW_HEIGHT)

	for !rl.WindowShouldClose() {
		width = f32(rl.GetScreenWidth())
		height = f32(rl.GetScreenHeight())

		check_inputs(data)
		draw(data, width, height)
	}
}
