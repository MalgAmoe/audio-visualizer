package audio

import "core:fmt"
import "core:math"


// ---------- SIGNAL STATS ----------

calculate_rms :: proc(buffer: []f32) -> f32 {
	N := len(buffer)
	sum: f32 = 0
	for i in 0 ..< N {
		sum = sum + buffer[i] * buffer[i]
	}

	return math.sqrt_f32(sum / f32(N))
}

stereo_correlation :: proc(frame: []f32) -> f32 {
	if len(frame) < 2 || len(frame) % 2 != 0 {
		return 0
	}

	sum_l: f32 = 0
	sum_r: f32 = 0
	sum_lr: f32 = 0
	sum_l_square: f32 = 0
	sum_r_square: f32 = 0

	len_frame := len(frame) / 2

	for i in 0 ..< len_frame {
		left := frame[2 * i]
		right := frame[2 * i + 1]

		sum_l += left
		sum_r += right
		sum_lr += left * right
		sum_l_square += left * left
		sum_r_square += right * right
	}

	n := f32(len_frame)
	covariance := (sum_lr - (sum_l * sum_r) / n) / n
	variance_l := (sum_l_square - (sum_l * sum_l) / n) / n
	variance_r := (sum_r_square - (sum_r * sum_r) / n) / n

	std_dev_l := math.sqrt(variance_l)
	std_dev_r := math.sqrt(variance_r)

	epsilon: f32 = 1e-8
	if std_dev_l < epsilon || std_dev_r < epsilon {
		return 0
	}

	correlation := covariance / (std_dev_l * std_dev_r)

	return math.clamp(correlation, -1, 1)
}


// ---------- FFT ----------

fft :: proc($N: int, x: [N]f32) -> (X: [N]complex64) {
	steps := log2_int(N)

	// convert to complex
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

ifft :: proc($N: int, X: [N]complex64) -> (x: [N]complex64) {
	steps := log2_int(N)

	for i in 0 ..< N {
		x[i] = X[i]
	}

	// bit reverse input
	for k in 0 ..< N {
		rev_k := bit_reverse(k, steps)
		if rev_k > k {
			temp := x[k]
			x[k] = x[rev_k]
			x[rev_k] = temp
		}
	}

	// compute ifft
	for s in 1 ..= steps {
		m := 1 << uint(s)
		m_32 := f32(m)
		wm: complex64 = complex(math.cos_f32(2 * math.PI / m_32), math.sin_f32(2 * math.PI / m_32))

		for k := 0; k < N; k += m {
			w: complex64 = complex(1, 0)
			for j := 0; j < m / 2; j += 1 {
				t := w * x[k + j + m / 2]
				u := x[k + j]
				x[k + j] = u + t
				x[k + j + m / 2] = u - t
				w *= wm
			}
		}
	}

	scale := 1.0 / f32(N)
	for i in 0 ..< N {
		x[i] = x[i] * complex(scale, 0)
	}

	return x
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

log2_int :: proc(n: int) -> int {
	assert(((n & (n - 1)) == 0), "Input size must be power of 2")
	count := 0
	value := n
	for value > 1 {
		value >>= 1
		count += 1
	}
	return count
}


// ---------- SPECTRUM ----------

compute_spectrum :: proc($N: int, fft_out: [N]complex64) -> (spectrum: [N]f32) {
	for i in 0 ..< N {
		re := real(fft_out[i])
		im := imag(fft_out[i])
		magnitude := math.max(math.sqrt(re * re + im * im) / f32(N), 1e-20)
		spectrum[i] = 20 * math.log10(magnitude)
	}

	return spectrum
}

spectral_centroid :: proc($N: int, sample_rate: int, magnitude_bins: [N]f32) -> f32 {
	f_times_mag: f32 = 0
	total_mag: f32 = 0
	bin_width := f32(sample_rate / N)

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

spectral_spread :: proc($N: int, sample_rate: int, magnitude_bins: [N]f32, centroid: f32) -> f32 {
	sum_squared_deviation: f32 = 0
	sum_amplitude: f32 = 0
	bin_width := f32(sample_rate / N)

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

spectral_flux :: proc($N: int, spectrum: [N]f32, old_spectrum: [N]f32) -> f32 {
	sum_square_differences: f32 = 0
	for i in 0 ..< N {
		difference := spectrum[i] - old_spectrum[i]
		rectified_difference := math.max(0, difference)
		sum_square_differences += rectified_difference * rectified_difference
	}

	return math.sqrt(sum_square_differences)
}

spectral_phase :: proc(
	$N: int,
	left_fft: [N]complex64,
	right_fft: [N]complex64,
) -> (
	phases: [N / 2]Phase,
) {
	for i in 0 ..< len(phases) {
		left_im := imag(left_fft[i])
		left_re := real(left_fft[i])
		right_im := imag(right_fft[i])
		right_re := real(right_fft[i])

		left_mag := math.sqrt(left_re * left_re + left_im * left_im)
		right_mag := math.sqrt(right_re * right_re + right_im * right_im)

		left_phase := math.atan2(left_im, left_re)
		right_phase := math.atan2(right_im, right_re)


		phase_diff := right_phase - left_phase
		phases[i] = Phase {
			phase     = phase_diff / (2 * math.PI),
			magnitude = 20 * math.log10((left_mag + right_mag) * 0.5),
		}
	}

	return phases
}


// ---------- WINDOWING ----------

hann_window :: proc($N: int) -> [N]f32 {
	window: [N]f32
	for i in 0 ..< N {
		window[i] = 0.5 * (1.0 - math.cos(2.0 * math.PI * f32(i) / f32(N - 1)))
	}
	return window
}


// ---------- HELPERS ----------

stereo_buffer_to_mono :: proc(buffer: []f32, mono_buffer: []f32) {
	for &sample, i in mono_buffer {
		sample = (buffer[2 * i] + buffer[2 * i + 1]) * 0.5
	}
}

get_buffer_left_and_right :: proc(
	$N: int,
	buffer: [N]f32,
) -> (
	l_buffer: [N / 2]f32,
	r_buffer: [N / 2]f32,
) where (N & (N - 1)) ==
	0 {
	n := N / 2

	for i in 0 ..< n {
		l_buffer[i] = buffer[2 * i]
		r_buffer[i] = buffer[2 * i + 1]
	}

	return l_buffer, r_buffer
}

linear_to_log_freq :: proc(f: f32) -> f32 {
	min_freq := f32(20)
	max_freq := f32(20000)
	if (f < 20) do return 0
	return math.log10_f32(f / min_freq) / math.log10_f32(max_freq / min_freq)
}
