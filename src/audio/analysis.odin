package audio

import "core:math"

calculate_rms :: proc(buffer: []f32) -> f32 {
	N := len(buffer)
	sum: f32 = 0
	for i in 0 ..< N {
		sum = sum + buffer[i] * buffer[i]
	}

	return math.sqrt_f32(sum / f32(N))
}

fft :: proc(x: []f32) -> []complex64 {
	N := len(x)
	steps := int(math.log2(f16(N)))

	assert(((N & (N - 1)) == 0), "In put size must be power of 2")

	// convert to complex
	X: []complex64 = make([]complex64, N)
	for i in 0 ..< N {
		X[i] = complex(x[i], 0)
	}

	// bit reverse input
	for k in 0 ..< N {
		rev_k := bit_reverse(k, steps)
		if rev_k > k {
			temp := X[k]
			X[k] = X[rev_k]
			X[rev_k] = temp
		}
	}

	// compute fft
	for s in 1 ..= steps {
		m := 1 << uint(s)
		m_32 := f32(m)
		wm: complex64 = complex(
			math.cos_f32(-2 * math.PI / m_32),
			math.sin_f32(-2 * math.PI / m_32),
		)

		for k := 0; k < N; k += m {
			w: complex64 = complex(1, 0)
			for j := 0; j < m / 2; j += 1 {
				t := w * X[k + j + m / 2]
				u := X[k + j]
				X[k + j] = u + t
				X[k + j + m / 2] = u - t
				w *= wm
			}
		}
	}

	return X
}

bit_reverse :: proc(value: int, bits: int) -> int {
	result := 0
	current_value := value
	for i in 0 ..< bits {
		result = (result << 1) | (current_value & 0x1)
		current_value >>= 1
	}
	return result
}

compute_spectrum :: proc(fft_out: []complex64) -> []f32 {
	N := len(fft_out) / 2
	spectrum: []f32 = make([]f32, N)

	for i in 0 ..< N {
		re := real(fft_out[i])
		im := imag(fft_out[i])
		magnitude := math.max(math.sqrt(re * re + im * im) / f32(N), 1e-20)
		spectrum[i] = math.log10(magnitude)
	}

	return spectrum
}

hann_window :: proc($N: int) -> [N]f32 {
	window: [N]f32
	for i in 0 ..< N {
		window[i] = 0.5 * (1.0 - math.cos(2.0 * math.PI * f32(i) / f32(N - 1)))
	}
	return window
}

calc_position :: proc(f: f32) -> f32 {
	min_freq := f32(10) // Lowest frequency we need
	max_freq := f32(20000) //  Highest frequency we need
	if (f < 20) do return 0
	return math.log10_f32(f / min_freq) / math.log10_f32(max_freq / min_freq)
}
