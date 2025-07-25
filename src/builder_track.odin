package main
import "core:bytes"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:strconv"
import s "core:strings"
import "core:text/edit"
import "core:unicode"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"

Track_Steps_Signals :: [32]Individual_Step_Signals

Track_Button_Signals :: struct {
	enable_signals:    Box_Signals,
	file_load_signals: Box_Signals,
}

Track_Control_Signals :: struct {
	value:          f32,
	max:            f32,
	grip_signals:   Box_Signals,
	track_signals:  Box_Signals,
	button_signals: Track_Button_Signals,
}

Individual_Step_Signals :: struct {
	pitch:  Box_Signals,
	volume: Box_Signals,
	send1:  Box_Signals,
	send2:  Box_Signals,
}

Num_Step_Input_Signals :: struct {
	box_signals: Box_Signals,
}

// Obviously not a complete track, but as complete-ish for now :).
create_track :: proc(which: u32, track_width: f32) -> Track_Steps_Signals {
	track_rect := cut_rect(top_rect(), RectCut{Size{.Pixels, track_width}, .Left})
	track_controlls_rect := cut_rect(&track_rect, RectCut{Size{.Percent, 0.20}, .Bottom})
	track_container := container(
		tprintf("container@track-{}-container", which),
		track_rect,
		Track_Control_Metadata{which, {}},
	)

	push_parent_rect(&track_rect)
	push_parent_rect(&track_controlls_rect)
	track_controls := track_control(
		tprintf("controls@track-{}-controls", which),
		&track_controlls_rect,
		app.audio_state.tracks[which].volume,
		which,
	)
	pop_parent_rect()
	track_step_container := top_rect()
	steps := track_steps(fmt.tprintf("steps@track-{}-steps", which), track_step_container, which)
	pop_parent_rect()

	handle_track_steps_interactions(steps, which)
	handle_track_control_interactions(&track_controls, which)

	return steps
}

pitch_step :: proc(id_string: string, rect: Rect, metadata: Step_Metadata) -> Box_Signals {
	if type_of(metadata) != Step_Metadata {
		panic(tprintf("pitch setp was created with Step_Metadata. id_string = {}", id_string))
	}
	signals := text_input(id_string, rect, metadata)
	return signals
}

num_step :: proc(id_string: string, rect: Rect, metadata: Step_Metadata, min, max: int) -> Box_Signals {
	signals := num_input(id_string, rect, min, max, metadata)
	return signals
}

track_steps :: proc(id_string: string, rect: ^Rect, which: u32) -> Track_Steps_Signals {
	step_height := rect_height(rect^) / 32
	steps: Track_Steps_Signals
	// Shouldn't hardcode num of steps.
	for i: u32 = 0; i < 32; i += 1 {
		track_name := get_name_from_id_string(id_string)
		steps_rect := cut_rect(rect, {Size{.Pixels, step_height}, .Top})
		step_width := rect_height(steps_rect)
		each_steps_rect := cut_rect_into_n_horizontally(steps_rect, 4)

		// If track sampler is in slice mode, pitches should be slice numbers
		// else they should just be notes to be played in 1 shot mode.
		sampler := app.samplers[which]

		push_color(palette.primary.s_500)
		pitch_box: Box_Signals
		if sampler.mode == .slice {
			pitch_box = num_step(
				create_subset_id(i, which, .Pitch_Slice),
				each_steps_rect[0],
				Step_Metadata{which, i, .Pitch_Slice},
				0,
				10,
				// sampler.n_slices > 0 ? int(sampler.n_slices - 1) : 0,
			)
		} else {
			pitch_box = pitch_step(
				create_subset_id(i, which, .Pitch_Note),
				each_steps_rect[0],
				Step_Metadata{which, i, .Pitch_Note},
			)
		}

		push_color(palette.secondary.s_500)
		volume_box := num_step(
			create_subset_id(i, which, .Volume),
			each_steps_rect[1],
			Step_Metadata{which, i, .Volume},
			0,
			100,
		)

		push_color(palette.secondary.s_400)
		step1_box := num_step(
			create_subset_id(i, which, .Send1),
			each_steps_rect[2],
			Step_Metadata{which, i, .Send1},
			0,
			100,
		)

		push_color(palette.secondary.s_400)
		step2_box := num_step(
			create_subset_id(i, which, .Send2),
			each_steps_rect[3],
			Step_Metadata{which, i, .Send2},
			0,
			100,
		)

		individual_step := Individual_Step_Signals {
			pitch  = pitch_box,
			volume = volume_box,
			send1  = step1_box,
			send2  = step2_box,
		}
		clear_color_stack()

		steps[i] = individual_step
	}
	return steps
}

handle_track_steps_interactions :: proc(track: Track_Steps_Signals, which: u32) {
	for step in track {
		pitch_box := step.pitch.box
		volume_box := step.volume.box
		send1_box := step.send1.box
		send2_box := step.send2.box
		if step.pitch.clicked {
			enable_step(pitch_box)
		}
		if pitch_box.selected && pitch_box.signals.scrolled {
			if pitch_box.signals.scrolled_up {
				if app.samplers[which].mode == .slice {
					curr_value := strconv.atoi(pitch_box.value.(Step_Value_Type).(string))
					if curr_value == int(app.samplers[which].n_slices) {return}
					new_value := curr_value + 1
					// need to figure out how to not permanently allocate this thing, or atleast figure out when to free it.
					conv_buf := make_dynamic_array_len([dynamic]u8, 10)
					pitch_box.value = strconv.itoa(conv_buf[:], new_value)
				} else {
					new_value := up_one_semitone(pitch_box.value.?.(string))
					copy(pitch_box.value_buffer[:], new_value)
					pitch_box.value = string(pitch_box.value_buffer[:len(new_value)])
				}
			} else {
				if app.samplers[which].mode == .slice {
					curr_value := strconv.atoi(pitch_box.value.(Step_Value_Type).(string))
					if curr_value == 0 {return}
					new_value := curr_value - 1
					// need to figure out how to not permanently allocate this thing, or atleast figure out when to free it.
					conv_buf := make_dynamic_array_len([dynamic]u8, 10)
					pitch_box.value = strconv.itoa(conv_buf[:], new_value)
				} else {
					new_value := down_one_semitone(pitch_box.value.?.(string))
					copy(pitch_box.value_buffer[:], new_value)
					pitch_box.value = string(pitch_box.value_buffer[:len(new_value)])

				}
			}
		}
		if volume_box.signals.scrolled {
			change := volume_box.signals.scrolled_up ? 1 : -1
			step_num_modify_value(volume_box, 0, 100, change)
		}
		if send1_box.signals.scrolled {
			change := send1_box.signals.scrolled_up ? 1 : -1
			step_num_modify_value(send1_box, 0, 100, change)
		}
		if send2_box.signals.scrolled {
			change := send2_box.signals.scrolled_up ? 1 : -1
			step_num_modify_value(send2_box, 0, 100, change)
		}
	}
}

// This will break if not called with the step_pitch box.
enable_step :: proc(step_pitch_box: ^Box) {
	step_num := u32(step_num_from_step(step_pitch_box.id_string))
	track_num := u32(track_num_from_step(step_pitch_box.id_string))
	pitch_type := step_pitch_box.metadata.(Step_Metadata).step_type
	pitch_box := ui_state.box_cache[create_substep_input_id(step_num, track_num, pitch_type)]
	volume_box := ui_state.box_cache[create_substep_input_id(step_num, track_num, .Volume)]
	send1_box := ui_state.box_cache[create_substep_input_id(step_num, track_num, .Send1)]
	send2_box := ui_state.box_cache[create_substep_input_id(step_num, track_num, .Send2)]
	// step.pitch.box_signals.box.selected = !step.pitch.box_signals.box.selected
	pitch_box.selected = !pitch_box.selected
	if pitch_box.selected {
		ui_state.selected_steps[track_num][step_num] = true
		if pitch_box.value == nil || pitch_box.value.?.(string) == "" {
			pitch_box.value = pitch_type == .Pitch_Note ? "C3" : "0"
		}
		if volume_box.value == nil || volume_box.value.?.(string) == "" {
			volume_box.value = 50
		}
		if send1_box.value == nil {
			send1_box.value = 0
		}
		if send2_box.value == nil {
			send2_box.value = 0
		}
	} else {
		ui_state.selected_steps[track_num][step_num] = false
	}
}

// assumes 0 <= value <= 100
track_control :: proc(id_string: string, rect: ^Rect, value: f32, which: u32) -> Track_Control_Signals {
	id := get_id_from_id_string(id_string)
	buttons_rect := cut_rect(rect, {Size{.Percent, 0.1}, .Bottom})
	enable_track_button_rect := get_rect(buttons_rect, {Size{.Percent, 0.4}, .Left})
	enable_button_id := tprintf("{}@{}_button", app.audio_state.tracks[which].armed ? "unarm" : "arm", id)
	push_color(palette.secondary.s_900)
	enable_track_button := text_button(
		enable_button_id,
		enable_track_button_rect,
		Track_Control_Metadata{which, .Enable_Button},
	)
	file_load_button_rect := get_rect(buttons_rect, {Size{.Percent, 0.4}, .Right})
	file_load_button := text_button(
		tprintf("load@{}_file_load_button", id),
		file_load_button_rect,
		Track_Control_Metadata{which, .File_Load_Button},
	)

	bpm_rect := cut_rect(rect, RectCut{Size{.Percent, 0.5}, .Left})
	bpm_rect = cut_bottom(&bpm_rect, {.Percent, 0.5})
	rects := cut_rect_into_n_vertically(bpm_rect, 2)
	bpm_label_rect, bpm_input_rect := rects[0], rects[1]
	bpm_label := text_container(tprintf("BPM:@bpm-label-track-{}", which), bpm_label_rect)
	ui_state.font_size = .s
	bpm_input := num_input(
		tprintf("bpm@bpm-input-track-{}", which),
		bpm_input_rect,
		0,
		100,
		metadata = Track_Control_Metadata{which, .BPM_Input},
		init_value = 120,
	)

	ui_state.z_index = 5
	defer ui_state.z_index = 0

	push_color(palette.secondary.s_500)
	slider_track_rect := cut_rect(rect, RectCut{Size{.Percent, 1}, .Left})
	slider_track_rect = shrink_x(slider_track_rect, {.Percent, 0.8})
	slider_track := box_from_cache(
		{.Scrollable, .Draw, .Clickable},
		tprintf("slider-track@track-{}-slider-track", which),
		slider_track_rect,
	)
	append(&ui_state.temp_boxes, slider_track)

	slider_grip_rect := get_bottom(slider_track.rect, Size{.Pixels, 30})
	slider_grip_rect = expand_x(slider_grip_rect, Size{.Percent, 0.5})
	slider_grip_rect.bottom_right.y -= (value / 100) * rect_height(slider_track_rect)
	slider_grip_rect.top_left.y -= (value / 100) * rect_height(slider_track_rect)

	slider_grip := box_from_cache(
		{.Clickable, .Hot_Animation, .Active_Animation, .Draggable, .Draw},
		tprintf("grip@track-{}-grip", id),
		slider_grip_rect,
		Track_Control_Metadata{which, .Volume_Slider},
	)
	append(&ui_state.temp_boxes, slider_grip)
	clear_color_stack()
	return Track_Control_Signals {
		value = value,
		max = 100,
		grip_signals = box_signals(slider_grip),
		track_signals = box_signals(slider_track),
		button_signals = {enable_track_button, file_load_button},
	}
}

handle_track_control_interactions :: proc(t_controls: ^Track_Control_Signals, which: u32) {
	if t_controls.track_signals.scrolled_down ||
	   t_controls.track_signals.scrolled_up ||
	   t_controls.grip_signals.scrolled_down ||
	   t_controls.grip_signals.scrolled_up {
		app.audio_state.tracks[which].volume = calc_slider_grip_val(
			app.audio_state.tracks[which].volume,
			100,
			t_controls.track_signals.scrolled_up || t_controls.grip_signals.scrolled_up,
		)
		set_volume(
			app.audio_state.tracks[which].sound,
			map_range(0, 100, 0, 1, app.audio_state.tracks[which].volume),
		)
		printfln("value before scrolling: {}", app.audio_state.tracks[which].volume)
	}
	if t_controls.button_signals.enable_signals.clicked {
		armed_state := app.audio_state.tracks[which].armed
		app.audio_state.tracks[which].armed = !armed_state
	}
	if t_controls.button_signals.file_load_signals.clicked {
		files, ok := file_dialog(false)
		assert(ok, "file dialog failed :(")
		printfln("{} returned from file dialog", files)
		set_track_sound(files[0], which)
	}
}

// Max is 0, min is pixel_height(slider), this is because the co-ord system of our layout.
calc_slider_grip_val :: proc(current_val: f32, max: f32, up: bool) -> f32 {
	proposed_value := current_val + (3 * (up ? 1 : -1))
	if proposed_value < 0 {
		return 0
	} else if proposed_value > max {
		return max
	} else {
		return proposed_value
	}
}

// broke this out because it can be called in various circumstances:
// arrow keys, vim keys, scrolling, (maybe dragging in the future).
step_num_modify_value :: proc(box: ^Box, min, max, change: int) {
	box_value, has_value := box.value.?
	if has_value {
		switch _ in box_value {
		case string:
			value_as_int := strconv.atoi(box.value.?.(string))
			box_value = clamp(u32(value_as_int + change), u32(min), u32(max))
			box.value = box_value
		case u32:
			box_value = clamp(u32(int(box.value.?.(u32)) + change), u32(min), u32(max))
			box.value = box_value
		}
	} else {
		box.value = change != 0 ? u32(change) : nil
	}
}

step_num_from_step :: proc(id_string: string) -> u32 {
	if id_string in ui_state.box_cache {
		box := ui_state.box_cache[id_string]
		metadata := box.metadata.(Step_Metadata)
		return metadata.step_num
	} else {
		panic("tried to get step num from a step whose ID doesn't exist!!!")
	}
}

track_num_from_step :: proc(id_string: string) -> u32 {
	if id_string in ui_state.box_cache {
		box := ui_state.box_cache[id_string]
		metadata := box.metadata.(Step_Metadata)
		return metadata.track_num
	} else {
		panic("tried to get track num from a step whose ID doesn't exist!!!")
	}
}

dropped_on_track :: proc() -> (u32, bool) {
	return 0, false
	// mouse_x, mouse_y: i32
	// sdl.GetMouseState(&mouse_x, &mouse_y)
	// for i in 0 ..= N_TRACKS - 1 {
	// 	l := i32(f32(app.wx^) * f32(i) / f32(N_TRACKS))
	// 	r := i32(f32(app.wx^) * f32(i + 1) / f32(N_TRACKS))
	// 	printf("l: {}    r: {} ", l, r)
	// 	println("mouse state:", mouse_x)
	// 	println("i:", i, "i/ntracks:", f32(i) / f32(N_TRACKS))
	// 	if mouse_x >= l && mouse_x <= r {
	// 		return u32(i), true
	// 	}
	// }
	// return 0, false
}

// The different parts of a single step.
Track_Step_Part :: enum {
	Pitch_Note,
	Pitch_Slice,
	Volume,
	Send1,
	Send2,
}

create_subset_id :: proc(
	step_num, track_num: u32,
	type: Track_Step_Part,
	allocator: mem.Allocator = context.temp_allocator,
) -> string {
	switch type {
	case .Pitch_Note:
		return tprintf("step-{}-pitch@step-{}-pitch-track-{}", step_num, step_num, track_num)
	case .Pitch_Slice:
		return tprintf("step-{}-slice-num@step-{}-slice-num-track-{}", step_num, step_num, track_num)
	case .Volume:
		return tprintf("step-{}-volume@step-{}-volume-track-{}", step_num, step_num, track_num)
	case .Send1:
		return tprintf("step-{}-send1@step-{}-send1-track-{}", step_num, step_num, track_num)
	case .Send2:
		return tprintf("step-{}-send2@step-{}-send2-track-{}", step_num, step_num, track_num)
	case:
		panic("switch on type_of(Track_Step_Part) didn't trigger any case")
	}
}

create_substep_input_id :: proc(
	step_num, track_num: u32,
	type: Track_Step_Part,
	allocator: mem.Allocator = context.temp_allocator,
) -> string {
	switch type {
	case .Pitch_Note:
		return tprintf("{}-text-input", create_subset_id(step_num, track_num, .Pitch_Note))
	case .Pitch_Slice:
		return tprintf("{}-text-input", create_subset_id(step_num, track_num, .Pitch_Slice))
	case .Volume:
		return tprintf("{}-text-input", create_subset_id(step_num, track_num, .Volume))
	case .Send1:
		return tprintf("{}-text-input", create_subset_id(step_num, track_num, .Send1))
	case .Send2:
		return tprintf("{}-text-input", create_subset_id(step_num, track_num, .Send2))
	case:
		panic("switch on type_of(Track_Step_Part) didn't trigger any case")
	}
}

get_substeps_input_from_step :: proc(
	step_num, track_num: u32,
) -> (
	pitch_box, volume_box, send1_box, send2_box: ^Box,
) {
	if app.samplers[track_num].mode == .slice {
		pitch_box = ui_state.box_cache[create_substep_input_id(step_num, track_num, .Pitch_Slice)]
	} else {
		pitch_box = ui_state.box_cache[create_substep_input_id(step_num, track_num, .Pitch_Note)]
	}
	volume_box = ui_state.box_cache[create_substep_input_id(step_num, track_num, .Volume)]
	send1_box = ui_state.box_cache[create_substep_input_id(step_num, track_num, .Send1)]
	send2_box = ui_state.box_cache[create_substep_input_id(step_num, track_num, .Send2)]
	return pitch_box, volume_box, send1_box, send2_box
}
