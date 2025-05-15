package audio

import "core:fmt"
import "core:math"


// ----- SIMPLE SINE WAVE -----

SINE_WAVETABLE_SIZE: int : 128

create_sine_wavetable :: proc() -> [SINE_WAVETABLE_SIZE]f32 {
	wavetable: [SINE_WAVETABLE_SIZE]f32
	for i in 0 ..< SINE_WAVETABLE_SIZE {
		phase := (f32(i) / f32(SINE_WAVETABLE_SIZE)) * 2 * math.PI
		wavetable[i] = math.sin(phase)
	}
	return wavetable
}

SineOsc :: struct {
	freq:     f32,
	sine_idx: f32,
	wave:     ^[SINE_WAVETABLE_SIZE]f32,
}

sine_wave := create_sine_wavetable()

SineOsc_create :: proc(freq: f32 = 100) -> SineOsc {
	return {freq = freq, sine_idx = 0, wave = &sine_wave}
}

SineOsc_nextValue_linear :: proc(osc: ^SineOsc, mod: f32 = 1) -> f32 {
	if (osc.sine_idx > 1) {
		osc.sine_idx -= 1
	}
	index_float := osc.sine_idx * f32(SINE_WAVETABLE_SIZE)
	index := int(index_float) % SINE_WAVETABLE_SIZE
	next_index := (index + 1) % SINE_WAVETABLE_SIZE
	fractional := index_float - f32(int(index_float))
	sample := osc.wave[index] * (1 - fractional) + osc.wave[next_index] * fractional

	incr := mod * osc.freq / f32(SAMPLE_RATE)
	osc.sine_idx += incr

	return sample
}

SineOsc_nextValue_raw :: proc(osc: ^SineOsc, mod: f32 = 1) -> f32 {
	index_float := osc.sine_idx * f32(SINE_WAVETABLE_SIZE)
	index := int(index_float) % SINE_WAVETABLE_SIZE
	sample := osc.wave[index]

	incr := mod * osc.freq / f32(SAMPLE_RATE)
	osc.sine_idx += incr
	if (osc.sine_idx > 1) {
		osc.sine_idx -= 1
	}

	return sample
}

SineOsc_retrig :: proc(osc: ^SineOsc, volume: f32 = 0) {
	if (volume == 0) {
		osc.sine_idx = 0.25
	} else {
		osc.sine_idx = (osc.sine_idx + 0.25)
		if osc.sine_idx > 1 {
			osc.sine_idx -= 1
		}
	}
}
