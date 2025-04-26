package main
import ma "vendor:miniaudio"

Sampler_Signals :: struct {
	container_signals: Draggable_Container_Signals,
}
sampler :: proc(id_string: string, rect: ^Rect) -> Sampler_Signals {
	sampler_name := get_name_from_id_string(id_string)
	ui_state.z_index = 2
	defer ui_state.z_index = 0
	s_container := draggable_container(tprintf("{}-container@{}-container", sampler_name, get_id_from_id_string(id_string)), rect)
	s_rect := s_container.container.box.rect
	waveform_container := get_top(s_rect, {.Percent, 0.95})
	cut_top(&waveform_container, {.Percent, 0.1})
	sampler_controls_rect := cut_bottom(&waveform_container, {.Percent, 0.1})
	cut_left(&waveform_container, {.Percent, 0.1})
	cut_right(&waveform_container, {.Percent, 0.1})
	container(tprintf("{}-waveform-container@{}-waveform-container", sampler_name, get_id_from_id_string(id_string)), waveform_container)
	// At the moment we hardcode check the first track, obviously this isn't the expected behaviour long term.
	if app.audio_state.pcm_data[0] == nil || len(app.audio_state.pcm_data[0]) == 0 {
		store_track_pcm_data(0)
		println("writing out pcm data")
	}

	knob(
		"sampler_knob",
		Rect{sampler_controls_rect.top_left.xy, {sampler_controls_rect.bottom_right.x / 4, sampler_controls_rect.bottom_right.y}},
	)
	return Sampler_Signals{container_signals = s_container}
}
