package main
import "core:fmt"
import ma "vendor:miniaudio"

Track_Step_Signals :: [32][4]Box_Signals
tracker_step :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache(
		{.Draw, .Clickable, .Active_Animation, .Draw_Text, .Edit_Text},
		id_string,
		rect,
	)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
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
			fmt.aprintf("%s_step%d_beat1", track_name, i, allocator = context.temp_allocator),
			beat1,
		)

		beat2 := cut_rect(&step_rect, {Size{.Pixels, beat_rect_width}, .Left})
		b2_step := tracker_step(
			fmt.aprintf("%s_step%d_beat2", track_name, i, allocator = context.temp_allocator),
			beat2,
		)

		beat3 := cut_rect(&step_rect, {Size{.Pixels, beat_rect_width}, .Left})
		b3_step := tracker_step(
			fmt.aprintf("%s_step%d_beat3", track_name, i, allocator = context.temp_allocator),
			beat3,
		)

		beat4 := cut_rect(&step_rect, {Size{.Pixels, beat_rect_width}, .Left})
		b4_step := tracker_step(
			fmt.aprintf("%s_step%d_beat4", track_name, i, allocator = context.temp_allocator),
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

// Obviously not a complete track, but as complete-ish for now :).
create_track :: proc(which: u32, track_width: f32) -> Track_Step_Signals {
	track_container := cut_rect(top_rect(), RectCut{Size{.Pixels, track_width}, .Left})
	track_controller_container := cut_rect(&track_container, RectCut{Size{.Percent, 0.3}, .Bottom})
	push_parent_rect(&track_container)
	push_parent_rect(&track_controller_container)
	track_controls_0 := track_controls(
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
	handle_track_control_interactions(&track_controls_0, which)
	return steps
}

handle_track_control_interactions :: proc(t_controls: ^Track_Control_Signals, which: u32) {
	if t_controls.track_signals.scrolled {
		slider_volumes[which] = calc_slider_grip_val(slider_volumes[which], 100)
		ma.sound_set_volume(engine_sounds[which], map_range(0, 100, 0, 1, slider_volumes[which]))
	}
	if t_controls.button_signals.play_signals.clicked {
		toggle_sound(engine_sounds[which])
	}
	if t_controls.button_signals.file_load_signals.clicked {
		// println(osd.path(.Open_Dir))
	}
}

handle_track_steps_interactions :: proc(track: Track_Step_Signals) {
	for step in track {
		for beat in step {
			if beat.hovering {
				beat.box.hot = true
				// println("this beat is HOT!", beat.box.id_string)
			}
		}
	}
}
