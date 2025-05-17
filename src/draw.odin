package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

import "audio"

draw :: proc(data: ^audio.Data, width: f32, height: f32) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.BLACK)

	draw_waveform_info(data, width, height)
	draw_spetrum_info(data, width, height)
	draw_phase_info(data, width, height)
}

draw_waveform_info :: proc(data: ^audio.Data, width: f32, height: f32) {
	rl.DrawText(fmt.ctprintf("rms: %f", data.rms), 10, 10, 20, rl.RAYWHITE)

	len_buffer := len(data.mono_buffer)

	for i in 0 ..< len_buffer - 1 {
		i_f := f32(i)
		x1 := (i_f / f32(len_buffer)) * width * 0.5
		y1 := ((1.0 - data.mono_buffer[i]) * (height * 0.25)) + 20
		x2 := ((i_f + 1) / f32(len_buffer)) * width * 0.5
		y2 := ((1.0 - data.mono_buffer[i + 1]) * (height * 0.25)) + 20

		rl.DrawLineEx({x1, y1}, {x2, y2}, 10 * data.rms, rl.RAYWHITE)
	}
}

draw_spetrum_info :: proc(data: ^audio.Data, width: f32, height: f32) {
	central_spectroid_str := fmt.ctprintf("spectral centroid: %d", int(data.spectral_centroid))
	rl.DrawText(central_spectroid_str, i32(width) - 250 - 5, 10, 20, rl.ORANGE)

	spectral_spread_str := fmt.ctprintf("spectral spread: %d", int(data.spectral_spread))
	rl.DrawText(spectral_spread_str, i32(width) - 250 - 5, 35, 20, rl.YELLOW)

	spectral_flux_str := fmt.ctprintf("spectral flux: %d", int(data.spectral_flux))
	rl.DrawText(spectral_flux_str, i32(width) - 250 - 5, 60, 20, rl.PURPLE)

	bins := len(data.spectrum)
	spacing := (f32(audio.SAMPLE_RATE)) / f32(bins)

	for i in 0 ..< (bins / 2) - 1 {
		// Calculate frequency of this bin and next bin
		freq1 := f32(i) * spacing
		freq2 := f32(i + 1) * spacing

		// Get normalized positions on log scale (0 to 1)
		pos1 := audio.linear_to_log_freq(freq1)
		pos2 := audio.linear_to_log_freq(freq2)

		// Convert to screen coordinates (use full width)
		x1 := (1 + pos1) * width * 0.5
		x2 := (1 + pos2) * width * 0.5

		// Normalize amplitude values - adjust these constants based on your actual spectrum values
		amplitude_min := f32(-120) // dB
		amplitude_max := f32(0) // dB

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

		rl.DrawLine(i32(x1), i32(y1), i32(x2), i32(y2), rl.SKYBLUE)
	}

	x_spectral_centroid := (1 + audio.linear_to_log_freq(data.spectral_centroid)) * width * 0.5
	y1 := height * 0.5
	y2 := (1 - 0.0625) * height * 0.5
	rl.DrawLineEx({x_spectral_centroid, y1}, {x_spectral_centroid, y2}, 3, rl.ORANGE)

	x_spectral_spread := (1 + audio.linear_to_log_freq(data.spectral_spread)) * width * 0.5
	rl.DrawLineEx({x_spectral_spread, y1}, {x_spectral_spread, y2}, 3, rl.YELLOW)

	y_spectral_flux := height * 0.5 - data.spectral_flux * 0.25
	x1 := width * 0.5
	x2 := (1 + 0.0625) * width * 0.5
	rl.DrawLineEx({x1, y_spectral_flux}, {x2, y_spectral_flux}, 3, rl.PURPLE)
}

draw_phase_info :: proc(data: ^audio.Data, width: f32, height: f32) {
	bins := len(data.spectral_phases)
	spacing := (f32(audio.SAMPLE_RATE)) / f32(bins)

	for phase, i in data.spectral_phases {
		freq := f32(i) * spacing
		pos := audio.linear_to_log_freq(freq)
		x := width * 0.75 + 0.25 * (width - 10) * phase.phase
		y := height - 40 - (height) * 0.4 * f32(pos)

		rl.DrawCircleV({x, y}, phase.magnitude * 0.1, rl.PINK)
	}

	x_stereo_correlation := width * 0.75 + (width * 0.25 - 50) * data.stereo_correlation
	y_stereo_correlation_1 := height - 10
	y_stereo_correlation_2 := y_stereo_correlation_1 - 10
	rl.DrawLineEx(
		{width * 0.5 + 50, y_stereo_correlation_1 - 5},
		{width - 50, y_stereo_correlation_1 - 5},
		10,
		rl.Color{255, 255, 255, 20},
	)
	rl.DrawLineEx(
		{x_stereo_correlation, y_stereo_correlation_1},
		{x_stereo_correlation, y_stereo_correlation_2},
		5,
		rl.PINK,
	)
	rl.DrawText("-1", i32(width) / 2 + 30, i32(y_stereo_correlation_1 - 12), 15, rl.PINK)
	rl.DrawText("1", i32(width) - 40, i32(y_stereo_correlation_1 - 12), 15, rl.PINK)
}
