package main
import "core:bytes"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:math/rand"
import "core:strconv"
import s "core:strings"
import "core:text/edit"
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
	pitch:  Text_Input_Signals,
	volume: Num_Step_Input_Signals,
	send1:  Num_Step_Input_Signals,
	send2:  Num_Step_Input_Signals,
}

Num_Step_Input_Signals :: struct {
	box_signals: Box_Signals,
	new_value:   u32,
}

// Obviously not a complete track, but as complete-ish for now :).
create_track :: proc(which: u32, track_width: f32) -> Track_Steps_Signals {
	track_rect := cut_rect(top_rect(), RectCut{Size{.Pixels, track_width}, .Left})
	track_controlls_rect := cut_rect(&track_rect, RectCut{Size{.Percent, 0.20}, .Bottom})
	track_container := container(tprintf("container@track-{}-container", which), track_rect)

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

pitch_step :: proc(id_string: string, rect: Rect) -> Text_Input_Signals {
	// b := box_from_cache({.Draw, .Clickable, .Active_Animation, .Draw_Border}, id_string, rect)
	signals := text_input(id_string, rect, "")
	return signals
}

num_step :: proc(id_string: string, rect: Rect) -> Num_Step_Input_Signals {
	// b := box_from_cache({.Draw, .Clickable, .Active_Animation, .Draw_Border}, id_string, rect)
	signals := step_num_input(id_string, rect)
	println("after step_num_input has run - app.chars_stored: {}", app.curr_chars_stored)
	return signals
}

track_steps :: proc(id_string: string, rect: ^Rect, which: u32) -> Track_Steps_Signals {
	step_height := rect_height(rect^) / 32
	color1: [4]f32 = {0.9, 0.5, 0.1, 1}
	steps: Track_Steps_Signals
	for i in 0 ..< 32 { 	// Shouldn't hardcode num of steps.
		track_name := get_name_from_id_string(id_string)
		steps_rect := cut_rect(rect, {Size{.Pixels, step_height}, .Top})
		step_width := rect_height(steps_rect)
		each_steps_rect := cut_rect_into_n_horizontally(&steps_rect, 4)

		push_color(palette.primary.s_500)
		step0 := pitch_step(
			fmt.tprintf("step-{}-pitch@step-{}-pitch-track{}", i, i, which),
			each_steps_rect[0],
		)
		push_color(palette.secondary.s_500)
		step1 := num_step(
			fmt.tprintf("step-{}-volume@step-{}-volume-track{}", i, i, which),
			each_steps_rect[1],
		)

		push_color(palette.secondary.s_400)
		step2 := num_step(
			fmt.tprintf("step-{}-send1@step-{}-send1-track{}", i, i, which),
			each_steps_rect[2],
		)

		push_color(palette.secondary.s_300)
		step3 := num_step(
			fmt.tprintf("step-{}-send2@step-{}-send2-track{}", i, i, which),
			each_steps_rect[3],
		)
		individual_step := Individual_Step_Signals {
			pitch  = step0,
			volume = step1,
			send1  = step2,
			send2  = step3,
		}
		clear_color_stack()

		steps[i] = individual_step
	}
	return steps
}

handle_track_steps_interactions :: proc(track: Track_Steps_Signals, which: u32) {
	for step in track {
		if step.pitch.box_signals.clicked {
			step.pitch.box_signals.box.selected = !step.pitch.box_signals.box.selected
			step_num := step_num_from_step(step.pitch.box_signals.box.id_string)
			if step.pitch.box_signals.box.selected {
				ui_state.selected_steps[which][step_num] = true
			} else {
				ui_state.selected_steps[which][step_num] = false
			}
		}
		if step.pitch.box_signals.hovering && step.pitch.box_signals.scrolled {
			step_num := step_num_from_step(step.pitch.box_signals.box.id_string)
			ui_state.step_pitches[which][step_num] += f32(app.mouse.wheel.y)
		}
	}
}

// assumes 0 <= value <= 100
track_control :: proc(
	id_string: string,
	rect: ^Rect,
	value: f32,
	which: u32,
) -> Track_Control_Signals {
	buttons_rect := cut_rect(rect, {Size{.Percent, 0.1}, .Bottom})
	enable_track_button_rect := get_rect(buttons_rect, {Size{.Percent, 0.4}, .Left})
	enable_button_id := tprintf(
		"{}@{}_button",
		app.audio_state.tracks[which].armed ? "unarm" : "arm",
		get_id_from_id_string(id_string),
	)
	push_color(palette.secondary.s_900)
	enable_track_button := text_button(enable_button_id, enable_track_button_rect)
	file_load_button_rect := get_rect(buttons_rect, {Size{.Percent, 0.4}, .Right})
	file_load_button := text_button(
		tprintf("load@{}_file_load_button", get_id_from_id_string(id_string)),
		file_load_button_rect,
	)

	slider_track_rect := cut_rect(rect, RectCut{Size{.Percent, 1}, .Left})
	slider_track_rect = shrink_x(slider_track_rect, {.Percent, 0.8})
	push_color(palette.secondary.s_500)
	slider_track := box_from_cache({.Scrollable, .Draw, .Clickable}, id_string, slider_track_rect)
	append(&ui_state.temp_boxes, slider_track)

	slider_grip_rect := get_bottom(slider_track.rect, Size{.Pixels, 30})
	slider_grip_rect = expand_x(slider_grip_rect, Size{.Percent, 0.5})

	space_below_grip := get_bottom(slider_track_rect, Size{.Percent, value / 100})
	slider_grip_rect.bottom_right.y -= (value / 100) * rect_height(slider_track_rect)
	slider_grip_rect.top_left.y -= (value / 100) * rect_height(slider_track_rect)
	slider_grip := box_from_cache(
		{.Clickable, .Hot_Animation, .Active_Animation, .Draggable, .Draw},
		tprintf(
			"{}{}@{}",
			get_name_from_id_string(id_string),
			"_grip",
			get_id_from_id_string(id_string),
		),
		slider_grip_rect,
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
	if t_controls.track_signals.scrolled || t_controls.grip_signals.scrolled {
		app.audio_state.tracks[which].volume = calc_slider_grip_val(
			app.audio_state.tracks[which].volume,
			100,
		)
		set_volume(
			app.audio_state.tracks[which].sound,
			map_range(0, 100, 0, 1, app.audio_state.tracks[which].volume),
		)
	}
	if t_controls.button_signals.enable_signals.clicked {
		armed_state := app.audio_state.tracks[which].armed
		app.audio_state.tracks[which].armed = !armed_state
	}
	if t_controls.button_signals.file_load_signals.clicked {
		files, fok := file_dialog(false)
		assert(fok)
		set_track_sound(files[0], which)
	}
}

// Max is 0, min is pixel_height(slider), this is because the co-ord system of our layout.
calc_slider_grip_val :: proc(current_val: f32, max: f32) -> f32 {
	proposed_value := current_val + (3 * cast(f32)app.mouse.wheel.y)
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
		l := i32(f32(app.wx^) * f32(i) / f32(N_TRACKS))
		r := i32(f32(app.wx^) * f32(i + 1) / f32(N_TRACKS))

		printf("l: {}    r: {} ", l, r)
		println("mouse state:", mouse_x)
		println("i:", i, "i/ntracks:", f32(i) / f32(N_TRACKS))
		if mouse_x >= l && mouse_x <= r {
			return u32(i), true
		}
	}
	return 0, false
}

// This code is fairly brittle as it relies on box id strings of steps being of a certain format.
step_num_from_step :: proc(id_string: string) -> u16 {
	name := get_name_from_id_string(id_string)
	index_of_num := s.index(name, "-")
	num := u16(strconv.atoi(name[index_of_num + 1:]))
	return num
}

track_num_from_step :: proc(id_string: string) -> u16 {
	track_id := get_id_from_id_string(id_string)
	start := s.index(track_id, "track") + len("track")
	num := cast(u16)strconv.atoi(track_id[start:])
	return num
}

step_num_input :: proc(id_string: string, rect: Rect) -> Num_Step_Input_Signals {
	b := box_from_cache(
		{.Draw, .Draw_Text, .Edit_Text, .Text_Left, .Clickable, .Draw_Border},
		tprintf("{}-text-input", id_string),
		rect,
		"",
	)
	signals := box_signals(b)
	curr_value: u32
	box_value, been_created := b.value.?
	if been_created {
		curr_value = 0
		switch _ in box_value {
		case string:
			panic("box.value was set as string in step_num_input()")
		case u32:
			curr_value = box_value.(u32)
		}

	}
	if app.ui_state.last_active_box == b {
		i: u32 = 0
		for i = 0; i < app.curr_chars_stored; i += 1 {
			keycode := app.char_queue[i]
			#partial switch keycode {
			case .UP, .k:
				curr_value += 1
			case .DOWN, .j:
				curr_value -= 1
			case .LEFT, .h:
				curr_value -= 10
			case .RIGHT, .l:
				curr_value += 10
			case .BACKSPACE:
				curr_value = 0
			case .DELETE:
				curr_value = 0
			case .ESCAPE:
				println("last active box set to nil")
				ui_state.last_active_box = nil
				ui_state.active_box = nil
				app.curr_chars_stored = 0
				break
			}
		}
		// We do this because not every key should be handled by the text input.
		// For example, the escape key, should remove focus from the current text box,
		// but NOT be consumed, and instead be consumed elsewhere in the UI.
		app.curr_chars_stored -= app.curr_chars_stored - i
		// app.curr_chars_stored = 0
	}
	printfln(
		"after handling events in num_step_input, curr_chars_stored: {}",
		app.curr_chars_stored,
	)
	// volume can't be negative.
	curr_value = curr_value > 0 ? curr_value : 0

	// Kind of jank, but this is how we differentiate
	// b.name = 
	append(&ui_state.temp_boxes, b)

	res := Num_Step_Input_Signals {
		box_signals = signals,
		new_value   = curr_value,
	}
	b.value = curr_value
	return res

}
