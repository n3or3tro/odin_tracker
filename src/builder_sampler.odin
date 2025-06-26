package main
import ma "vendor:miniaudio"

Sampler_Signals :: struct {
	container_signals: Draggable_Container_Signals,
}

// takes in the container that the controls will be drawn inside.
sampler_left_controls :: proc(container: ^Box) {
	rect := container.rect
	rects := cut_rect_into_n_vertically(rect, 3)
	r1 := rects[0]
	r2 := rects[1]
	r3 := rects[2]
	b1 := button("b1@left-controls-button1", r1)
	b2 := button("b1@left-controls-button2", r2)
	b3 := button("b1@left-controls-button3", r3)
}

sampler_bottom_controls :: proc(container: ^Box) {
	// Create ADSR controls
	adsr_rect := cut_left(&container.rect, {.Percent, 0.4})
	// test_button := button("test layout@flaskjdflaksjdf", cut_right(&container.rect, {.Percent, 0.2}))
	rects := cut_rect_into_n_horizontally(adsr_rect, 4)

	attack_rect := rect_to_square(rects[0])
	decay_rect := rect_to_square(rects[1])
	sustain_rect := rect_to_square(rects[2])
	release_rect := rect_to_square(rects[3])

	pack_to_left({&attack_rect, &decay_rect, &sustain_rect, &release_rect}, margin = 5)

	ui_state.font_size = .s
	attack_knob := knob("attack@sampler-attack-knob", &attack_rect)
	decay_knob := knob("decay@sampler-decay-knob", &decay_rect)
	sustain_knob := knob("sustain@sampler-sustain-knob", &sustain_rect)
	release_knob := knob("release@sampler-release-knob", &release_rect)
	ui_state.font_size = .l
}

sampler :: proc(id_string: string, rect: ^Rect) -> Sampler_Signals {
	sampler_name := get_name_from_id_string(id_string)
	ui_state.z_index = 2
	defer ui_state.z_index = 0

	sampler_container := draggable_container(
		tprintf("sampler-container@{}-container", get_id_from_id_string(id_string)),
		rect,
	)
	sampler_rect := sampler_container.container.box.rect

	left_controls_rect := cut_left(&sampler_rect, {.Percent, 0.13})
	left_controls_container := container("left-controls@left-controls-sampler", left_controls_rect).box
	sampler_left_controls(left_controls_container)

	bottom_controls_rect := cut_bottom(&sampler_rect, {.Percent, 0.1})
	bottom_controls_container := container(
		tprintf("container@bottom-controls-container"),
		bottom_controls_rect,
	)
	sampler_bottom_controls(bottom_controls_container.box)

	container(
		tprintf(
			"{}-waveform-container@{}-waveform-container",
			sampler_name,
			get_id_from_id_string(id_string),
		),
		sampler_rect,
	)

	// At the moment we hardcode check the first track, obviously this isn't the expected behaviour long term.
	if app.audio_state.tracks[0].pcm_data == nil || len(app.audio_state.tracks[0].pcm_data) == 0 {
		store_track_pcm_data(0)
		println("writing out pcm data")
	}

	return Sampler_Signals{container_signals = sampler_container}
}
