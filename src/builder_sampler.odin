package main
import ma "vendor:miniaudio"

sampler :: proc(name: string, rect: Rect) {
	cnt := container(tprintf("{}-container@sampler"), rect).box.rect
	waveform_container := get_top(cnt, {.Percent, 0.95})
	cut_top(&waveform_container, {.Percent, 0.1})
	cut_bottom(&waveform_container, {.Percent, 0.1})
	cut_left(&waveform_container, {.Percent, 0.1})
	cut_right(&waveform_container, {.Percent, 0.1})
	container(tprintf("{}-waveform-container@sampler"), waveform_container)
}
