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
		spectrum[i] = 20 * math.log10(magnitude)
	}

	return spectrum
}

spectral_centroid :: proc(magnitude_bins: []f32) -> f32 {
	f_times_mag: f32 = 0
	total_mag: f32 = 0

	bin_width := f32(SAMPLE_RATE) / f32(len(magnitude_bins))

	for i in 0 ..< int(len(magnitude_bins) / 2) {
		f_n := (f32(i) + 0.5) * bin_width
		magnitude := magnitude_bins[i]
		magnitude_linear := math.pow(10, magnitude / 20)

		f_times_mag = f_times_mag + f_n * magnitude_linear
		total_mag = total_mag + magnitude_linear
	}

	if total_mag < 0.0001 {
		return 0
	}

	return f_times_mag / total_mag
}

spectral_spread :: proc(magnitude_bins: []f32, centroid: f32) -> f32 {
	sum_squared_deviation: f32 = 0
	sum_amplitude: f32 = 0

	bin_width := f32(SAMPLE_RATE) / f32(len(magnitude_bins))

	for i in 0 ..< int(len(magnitude_bins) / 2) {
		f_n := (f32(i) + 0.5) * bin_width
		magnitude := magnitude_bins[i]
		magnitude_linear := math.pow(10, magnitude / 20)

		deviation := f_n - centroid
		sum_squared_deviation += deviation * deviation * magnitude_linear
		sum_amplitude += magnitude_linear
	}

	if sum_amplitude < 0.0001 {
		return 0
	}

	return math.sqrt(sum_squared_deviation / sum_amplitude)
}

spectral_flux :: proc(spectrum: []f32, old_spectrum: []f32) -> f32 {
	sum_square_differences: f32 = 0

	if (len(old_spectrum) < len(spectrum)) {
		return 0
	}

	for i in 0 ..< len(spectrum) {
		difference := spectrum[i] - old_spectrum[i]
		rectified_difference := math.max(0, difference)
		sum_square_differences += rectified_difference * rectified_difference
	}

	return math.sqrt(sum_square_differences)
}

hann_window :: proc($N: int) -> [N]f32 {
	window: [N]f32
	for i in 0 ..< N {
		window[i] = 0.5 * (1.0 - math.cos(2.0 * math.PI * f32(i) / f32(N - 1)))
	}
	return window
}

linear_to_log_freq :: proc(f: f32) -> f32 {
	min_freq := f32(20)
	max_freq := f32(20000)
	if (f < 20) do return 0
	return math.log10_f32(f / min_freq) / math.log10_f32(max_freq / min_freq)
}
