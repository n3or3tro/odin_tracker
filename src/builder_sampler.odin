package main
import ma "vendor:miniaudio"

Sampler_Signals :: struct {
	container_signals: Draggable_Container_Signals,
}
sampler :: proc(id_string: string, rect: ^Rect) -> Sampler_Signals {
	sampler_name := get_name_from_id_string(id_string)
	ui_state.z_index = 2
	defer ui_state.z_index = 0
	s_container := draggable_container(tprintf("{}-container@sampler", sampler_name), rect)
	s_rect := s_container.container.box.rect
	waveform_container := get_top(s_rect, {.Percent, 0.95})
	cut_top(&waveform_container, {.Percent, 0.1})
	cut_bottom(&waveform_container, {.Percent, 0.1})
	cut_left(&waveform_container, {.Percent, 0.1})
	cut_right(&waveform_container, {.Percent, 0.1})
	container(tprintf("{}-waveform-container@sampler", sampler_name), waveform_container)
	return Sampler_Signals{container_signals = s_container}
}
