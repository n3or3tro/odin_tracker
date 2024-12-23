package main
import "core:fmt"
import "core:math"
import s "core:strings"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"

Track_Button_Signals :: struct {
	play_signals:      Box_Signals,
	file_load_signals: Box_Signals,
}
Track_Control_Signals :: struct {
	value:          f32,
	max:            f32,
	grip_signals:   Box_Signals,
	track_signals:  Box_Signals,
	button_signals: Track_Button_Signals,
}
Track_Step_Signals :: [32][4]Box_Signals

// Obviously not a complete track, but as complete-ish for now :).
create_track :: proc(which: u32, track_width: f32) -> Track_Step_Signals {
	track_container := cut_rect(top_rect(), RectCut{Size{.Pixels, track_width}, .Left})
	track_controller_container := cut_rect(&track_container, RectCut{Size{.Percent, 0.3}, .Bottom})
	push_parent_rect(&track_container)
	push_parent_rect(&track_controller_container)
	track_controls := track_control(
		fmt.aprintf("track%d_controls@1", which, allocator = context.temp_allocator),
		&track_controller_container,
		slider_volumes[which],
	)
	pop_parent_rect()
	track_step_container := cut_rect(top_rect(), {Size{.Percent, 0.95}, .Top})
	steps := track_steps(
		fmt.aprintf("track_steps%d@1", which, allocator = context.temp_allocator),
		&track_step_container,
	)
	pop_parent_rect()

	handle_track_steps_interactions(steps)
	handle_track_control_interactions(&track_controls, which)
	return steps
}

track_steps :: proc(id_string: string, rect: ^Rect) -> Track_Step_Signals {
	step_size := rect_height(rect^) / 32
	steps: Track_Step_Signals
	for i in 0 ..= 31 {
		step_rect := cut_rect(rect, {Size{.Pixels, step_size}, .Top})
		beat_rect_width := rect_width(get_rect(step_rect, {Size{.Percent, 0.25}, .Left}))
		track_name := get_name_from_id_string(id_string)

		beat1 := cut_rect(&step_rect, {Size{.Pixels, beat_rect_width}, .Left})
		b1_step := tracker_step(
			fmt.aprintf("%s_step%d_beat1@1", track_name, i, allocator = context.temp_allocator),
			beat1,
		)

		beat2 := cut_rect(&step_rect, {Size{.Pixels, beat_rect_width}, .Left})
		b2_step := tracker_step(
			fmt.aprintf("%s_step%d_beat2@1", track_name, i, allocator = context.temp_allocator),
			beat2,
		)

		beat3 := cut_rect(&step_rect, {Size{.Pixels, beat_rect_width}, .Left})
		b3_step := tracker_step(
			fmt.aprintf("%s_step%d_beat3@1", track_name, i, allocator = context.temp_allocator),
			beat3,
		)

		beat4 := cut_rect(&step_rect, {Size{.Pixels, beat_rect_width}, .Left})
		b4_step := tracker_step(
			fmt.aprintf("%s_step%d_beat4@1", track_name, i, allocator = context.temp_allocator),
			beat4,
		)
		append(&ui_state.temp_boxes, b1_step.box)
		append(&ui_state.temp_boxes, b2_step.box)
		append(&ui_state.temp_boxes, b3_step.box)
		append(&ui_state.temp_boxes, b4_step.box)
		steps[i][0] = b1_step
		steps[i][1] = b2_step
		steps[i][2] = b3_step
		steps[i][3] = b4_step
	}
	return steps
}

// assumes 0 <= value <= 100
track_control :: proc(id_string: string, rect: ^Rect, value: f32) -> Track_Control_Signals {
	buttons_rect := cut_rect(rect, {Size{.Percent, 0.1}, .Bottom})
	play_button_rect := get_rect(buttons_rect, {Size{.Percent, 0.4}, .Left})
	play_button := button(
		fmt.aprintf(
			"%s_play_button@1",
			get_name_from_id_string(id_string),
			allocator = context.temp_allocator,
		),
		play_button_rect,
	)
	file_load_button_rect := get_rect(buttons_rect, {Size{.Percent, 0.4}, .Right})
	file_load_button := button(
		fmt.aprintf("%s_file_load_button@1", get_name_from_id_string(id_string)),
		file_load_button_rect,
	)

	cut_rect(rect, {Size{.Percent, 0.33}, .Left})

	slider_track_rect := cut_rect(rect, RectCut{Size{.Percent, 0.5}, .Left})
	slider_track := box_from_cache({.Scrollable, .Draw}, id_string, slider_track_rect)
	append(&ui_state.temp_boxes, slider_track)

	slider_grip_rect := get_bottom(slider_track.rect, Size{.Pixels, 30})
	slider_grip_rect = expand_x(slider_grip_rect, Size{.Percent, 0.5})

	space_below_grip := get_bottom(slider_track_rect, Size{.Percent, value / 100})
	slider_grip_rect.bottom_right.y -= (value / 100) * rect_height(slider_track_rect)
	slider_grip_rect.top_left.y -= (value / 100) * rect_height(slider_track_rect)
	slider_grip := box_from_cache(
		{.Clickable, .Hot_Animation, .Active_Animation, .Draggable, .Draw},
		fmt.aprintf(
			"%s%s@%s",
			get_name_from_id_string(id_string),
			"_grip",
			get_id_from_id_string(id_string),
			allocator = context.temp_allocator,
		),
		slider_grip_rect,
	)
	append(&ui_state.temp_boxes, slider_grip)

	return Track_Control_Signals {
		value = value,
		max = 100,
		grip_signals = box_signals(slider_grip),
		track_signals = box_signals(slider_track),
		button_signals = {play_button, file_load_button},
	}
}

tracker_step :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache(
		{.Draw, .Clickable, .Active_Animation, .Draw_Text, .Edit_Text},
		id_string,
		rect,
	)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

handle_track_control_interactions :: proc(t_controls: ^Track_Control_Signals, which: u32) {
	if t_controls.track_signals.scrolled {
		slider_volumes[which] = calc_slider_grip_val(slider_volumes[which], 100)
		ma.sound_set_volume(engine_sounds[which], map_range(0, 100, 0, 1, slider_volumes[which]))
	}
	if t_controls.button_signals.play_signals.hovering {
	}

	if t_controls.button_signals.play_signals.clicked {
		toggle_sound(engine_sounds[which])
	}
	if t_controls.button_signals.file_load_signals.clicked {
		files, fok := file_dialog(false)
		assert(fok)
		set_track_sound(files[0], which)
	}
}

handle_track_steps_interactions :: proc(track: Track_Step_Signals) {
	for step in track {
		for beat in step {
			if beat.hovering {
			}
		}
	}
}

// Max is 0, min is pixel_height(slider), this is because the co-ord system of our layout.
calc_slider_grip_val :: proc(current_val: f32, max: f32) -> f32 {
	proposed_value := current_val + (3 * cast(f32)ui_state.mouse.wheel.y)
	if proposed_value < 0 {
		return 0
	} else if proposed_value > max {
		return max
	} else {
		return proposed_value
	}
}

dropped_on_track :: proc() -> (u32, bool) {
	mouse_x, mouse_y: i32
	sdl.GetMouseState(&mouse_x, &mouse_y)
	for i in 0 ..= N_TRACKS - 1 {
		l := i32(f32(wx^) * f32(i) / f32(N_TRACKS))
		r := i32(f32(wx^) * f32(i + 1) / f32(N_TRACKS))

		printf("l: %d    r: %d ", l, r)
		println("mouse state:", mouse_x)
		println("i:", i, "i/ntracks:", f32(i) / f32(N_TRACKS))
		if mouse_x >= l && mouse_x <= r {
			return u32(i), true
		}
	}
	return 0, false
}
