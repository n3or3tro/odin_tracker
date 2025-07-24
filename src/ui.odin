package main
import "core:fmt"
import "core:math"
import alg "core:math/linalg"
import "core:mem"
import str "core:strings"
import "core:sys/posix"
import thread "core:thread"
import "core:time"
import gl "vendor:OpenGL"
import "vendor:fontstash"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"


Color :: [4]f32
HSLA_Color :: [4]f32

Z_Layer :: enum {
	default,
	first,
	second,
}

UI_State :: struct {
	box_cache:             Box_Cache, // cross-frame cache of boxes
	font_atlases:          Atlases,
	font_size:             Font_Size,
	temp_boxes:            [dynamic]^Box,
	first_frame:           bool, // dont want to render on the first frame
	rect_stack:            [dynamic]^Rect,
	settings_toggled:      bool,
	color_stack:           [dynamic]Color,
	font_size_stack:       [dynamic]Font_Size,
	selected_steps:        [MAX_TRACKS][32]bool,
	step_pitches:          [MAX_TRACKS][32]f32,
	ui_scale:              f32, // between 0.0 and 1.0.
	// Used to tell the core layer to override some value
	// of a box that's in the cache. Useful for parts of the code
	// where the box isn't easilly accessible (like in audio related stuff).
	override_color:        bool,
	override_rect:         bool,
	quad_vbuffer:          ^u32,
	quad_vabuffer:         ^u32,
	quad_shader_program:   u32,
	root_rect:             ^Rect,
	frame_num:             ^u64,
	// hot_id:              string,
	// active_id:           string,
	hot_box:               ^Box,
	active_box:            ^Box,
	selected_box:          ^Box,
	last_hot_box:          ^Box,
	last_active_box:       ^Box,
	z_index:               u8,
	context_menu_pos:      Vec2,
	context_menu_active:   bool,
	right_clicked_on:      ^Box,
	wav_rendering_data:    map[ma.sound][dynamic]Rect_Render_Data,
	// the visual space between border of text box and the text inside.
	text_box_padding:      u16,
	keyboard_mode:         bool,
	last_clicked_box:      ^Box,
	last_clicked_box_time: time.Time,
	// Added this to help with sorting out z-order event consumption.
	next_frame_signals:    map[string]Box_Signals,
	// Used to help with the various bugs I was having related to input for box.value and mutating box.value.
	steps_value_arena:     mem.Arena,
	steps_value_allocator: mem.Allocator,
}

num_column :: proc(track_height: u32, n_steps: u32) {
	num_col_rect := cut_rect(top_rect(), {{.Percent, track_steps_width_ratio}, .Left})
	step_height := f32(track_height) / f32(n_steps)
	for i in 0 ..< n_steps {
		curr_step := cut_top(&num_col_rect, {.Pixels, step_height})
		text_container(tprintf("{}:@number-column-row-{}", i, i), curr_step)
	}
}

track_steps_height_ratio: f32 = 0.80
track_steps_width_ratio: f32 = 0.04
n_track_steps: u32 = 32

main_tracker_panel :: proc() {
	col_height := cast(u32)(rect_height(top_rect()^) * track_steps_height_ratio)

	num_column(col_height, n_track_steps)

	track_padding: u32 = 10
	track_width: f32 = 200
	spacers := make_dynamic_array_len_cap([dynamic]^Box, 10, 10, context.temp_allocator)
	for i in 0 ..< app.n_tracks {
		create_track(u32(i), track_width)
		append(&spacers, spacer("spacer@spacer", RectCut{Size{.Pixels, f32(track_padding)}, .Left}))
	}

	add_track_rect := Rect {
		top_left     = {track_width * f32(app.n_tracks) + 100, f32(app.wy^ / 2) - 50},
		bottom_right = {track_width * f32(app.n_tracks) + 150, f32(app.wy^ / 2)},
	}

	ui_state.z_index = 5
	add_track := text_button("+@add-track-button", add_track_rect)
	ui_state.z_index = 0

	if add_track.clicked {
		app.n_tracks += 1
	}

	if app.sampler_open {
		sampler_top_left := app.sampler_pos
		sampler_bottom_right := Vec2{1000 + sampler_top_left.x, 500 + sampler_top_left.y}
		sampler_signals := sampler(
			"sampler@first-sampler",
			&Rect{sampler_top_left, sampler_bottom_right},
			get_active_track(),
		)
		if sampler_signals.container_signals.handle_bar.dragging {
			app.dragging_window = true
		}
		// if you have multiple floating windows this will get ugly pretty quick
		if app.dragging_window {
			change_in_x := app.mouse.last_pos.x - app.mouse.pos.x
			change_in_y := app.mouse.last_pos.y - app.mouse.pos.y
			app.sampler_pos.x -= f32(change_in_x)
			app.sampler_pos.y -= f32(change_in_y)
		}
	}

	// Handle keyboard navigation based on in order keys that were queued via 
	// querying sdl event stream.
	for i in 0 ..< app.curr_chars_stored {
		keycode := app.char_queue[i]
		#partial switch keycode {
		case .LEFT, .h:
			move_active_box_left()
		case .RIGHT, .l:
			move_active_box_right()
		case .UP, .k:
			move_active_box_up()
		case .DOWN, .j:
			move_active_box_down()
		case .TAB:
			first_box: ^Box
			if app.samplers[get_active_track()].mode == .slice {
				first_box = app.ui_state.box_cache[create_substep_input_id(0, 0, .Pitch_Slice)]
			} else {
				first_box = app.ui_state.box_cache[create_substep_input_id(0, 0, .Pitch_Note)]
			}
			ui_state.selected_box = first_box
			first_box.selected = true
		case .RETURN, .RETURN2:
			// ui_state.selected_box.active = true
			// ui_state.active_box = ui_state.selected_box
			enable_step(ui_state.selected_box)
		case .s:
			app.sampler_open = !app.sampler_open
		case .ESCAPE:
			ui_state.active_box = nil
			ui_state.selected_box.active = false
		}
	}

	// Handle keyboard navigation based on the state of keyboard keys held down,
	// pretty sure this will only be used for handling multikey keyboard shortcuts
	if app.keys_held[sdl.Scancode.T] &&
	   (app.keys_held[sdl.Scancode.LCTRL] || app.keys_held[sdl.Scancode.RCTRL]) {
		println("adding a new track")
		app.n_tracks += 1
		// hack to stop triggering this too many times
		app.keys_held[sdl.Scancode.T] = false
		// app.keys_held[sdl.Scancode.RCTRL] = false
		// app.keys_held[sdl.Scancode.LCTRL] = false
	}

}

second_panel :: proc() {
	space := Rect{{100, 100}, {600, 300}}
	rects := cut_rect_into_n_vertically(space, 3)
	input1 := text_input("text-input@input-1", rects[0])
	old_font_size := ui_state.font_size
	ui_state.font_size = .xl
	input2 := text_input("text-input@input-2", rects[1])
	ui_state.font_size = old_font_size
	// input3 := text_input("text-input@input-3", rects[2])
}

get_active_track :: proc() -> u32 {
	// Figure out relevant track wav.
	// If sampler was opened via right click it should be obvious
	// {.....}
	// If sample opened via 'hotkey' get the track that holds the selected step.
	if ui_state.selected_box != nil {
		return track_num_from_step(ui_state.selected_box.id_string)
	}
	return 0
	// If keyboard navigation hasn't started yet, then just render the .wav from the first track.
}

move_active_box_left :: proc() {
	box := app.ui_state.selected_box
	step_num := u32(step_num_from_step(box.id_string))
	track_num := u32(track_num_from_step(box.id_string))
	next_active_box_id: string
	data := box.metadata.(Step_Metadata)
	switch data.step_type {
	case .Pitch_Note, .Pitch_Slice:
		if track_num > 0 {
			next_active_box_id = create_substep_input_id(step_num, track_num - 1, .Send2)
		} else {
			return
		}
	case .Volume:
		if app.samplers[track_num].mode == .slice {
			next_active_box_id = create_substep_input_id(step_num, track_num, .Pitch_Slice)
		} else {
			next_active_box_id = create_substep_input_id(step_num, track_num, .Pitch_Note)
		}
	case .Send1:
		next_active_box_id = create_substep_input_id(step_num, track_num, .Volume)
	case .Send2:
		next_active_box_id = create_substep_input_id(step_num, track_num, .Send1)
	}
	next_box := ui_state.box_cache[next_active_box_id]
	box.selected = false
	next_box.selected = true
	ui_state.selected_box = next_box

}

move_active_box_right :: proc() {
	box := app.ui_state.selected_box
	step_num := u32(step_num_from_step(box.id_string))
	track_num := u32(track_num_from_step(box.id_string))
	next_active_box_id: string

	data := box.metadata.(Step_Metadata)
	switch data.step_type {
	case .Pitch_Note, .Pitch_Slice:
		next_active_box_id = create_substep_input_id(step_num, track_num, .Volume)
	case .Volume:
		next_active_box_id = create_substep_input_id(step_num, track_num, .Send1)
	case .Send1:
		next_active_box_id = create_substep_input_id(step_num, track_num, .Send2)
	case .Send2:
		if track_num < u32(app.n_tracks) - 1 {
			if app.samplers[track_num].mode == .slice {
				next_active_box_id = create_substep_input_id(step_num, track_num + 1, .Pitch_Slice)
			} else {
				next_active_box_id = create_substep_input_id(step_num, track_num + 1, .Pitch_Note)
			}
		} else {
			return
		}
	}
	next_box := ui_state.box_cache[next_active_box_id]
	box.selected = false
	next_box.selected = true
	ui_state.selected_box = next_box
}

move_active_box_up :: proc() {
	box := app.ui_state.selected_box
	step_num := step_num_from_step(box.id_string)
	track_num := u32(track_num_from_step(box.id_string))
	if (step_num == 0) {
		return
	}
	step_num -= 1
	next_active_box_id: string
	data := box.metadata.(Step_Metadata)
	switch data.step_type {
	case .Pitch_Note, .Pitch_Slice:
		if app.samplers[track_num].mode == .slice {
			next_active_box_id = create_substep_input_id(step_num, track_num, .Pitch_Slice)
		} else {
			next_active_box_id = create_substep_input_id(step_num, track_num, .Pitch_Note)
		}
	case .Volume:
		next_active_box_id = create_substep_input_id(step_num, track_num, .Volume)
	case .Send1:
		next_active_box_id = create_substep_input_id(step_num, track_num, .Send1)
	case .Send2:
		next_active_box_id = create_substep_input_id(step_num, track_num, .Send2)
	}
	next_box := ui_state.box_cache[next_active_box_id]
	box.selected = false
	next_box.selected = true
	ui_state.selected_box = next_box
}

move_active_box_down :: proc() {
	box := app.ui_state.selected_box
	step_num := step_num_from_step(box.id_string)
	track_num := u32(track_num_from_step(box.id_string))
	if (step_num >= u32(n_track_steps) - 1) {
		println("'moving' down into track controls ... JKS, that isn't implemented.")
		return
	}
	step_num += 1
	next_active_box_id: string
	data := box.metadata.(Step_Metadata)
	switch data.step_type {
	case .Pitch_Slice, .Pitch_Note:
		if app.samplers[track_num].mode == .slice {
			next_active_box_id = create_substep_input_id(step_num, track_num, .Pitch_Slice)
		} else {
			next_active_box_id = create_substep_input_id(step_num, track_num, .Pitch_Note)
		}
	case .Volume:
		next_active_box_id = create_substep_input_id(step_num, track_num, .Volume)
	case .Send1:
		next_active_box_id = create_substep_input_id(step_num, track_num, .Send1)
	case .Send2:
		next_active_box_id = create_substep_input_id(step_num, track_num, .Send2)
	}
	next_box := ui_state.box_cache[next_active_box_id]
	box.selected = false
	next_box.selected = true
	ui_state.selected_box = next_box
}

create_ui :: proc() {
	topbar := top_bar()
	handle_top_bar_interactions(topbar)
	switch app.active_tab {
	case 0:
		main_tracker_panel()
	case 1:
		second_panel()
	case 2:
		text_button_absolute("this is the conent of tab 3@whatalksj", 100, 100)
	}
	if ui_state.context_menu_active {
		context_menu()
	}
}

render_ui :: proc() {
	clear_screen()
	if ui_state.first_frame {
		return
	}
	rect_rendering_data := get_all_rendering_data()
	n_rects := u32(len(rect_rendering_data))
	populate_vbuffer_with_rects(
		ui_state.quad_vabuffer,
		0,
		raw_data(rect_rendering_data^),
		n_rects * size_of(Rect_Render_Data),
	)
	gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, i32(n_rects))

	delete_dynamic_array(rect_rendering_data^)
	reset_ui_state()
}

reset_ui_state :: proc() {
	/* 
		I think maybe I don't want to actually reset this each frame, for exmaple,
		if a user selected some input field on one frame, then it should still be active
		on the next fram
	*/

	if ui_state.active_box != nil {
		ui_state.last_active_box = ui_state.active_box
	}
	if ui_state.hot_box != nil {
		ui_state.last_hot_box = ui_state.hot_box
	}
	ui_state.active_box = nil
	ui_state.hot_box = nil
}

/* ------- stuff for a theme / color system -------------- */
Color_Theme :: struct {
	primary:       Color,
	primary_var:   Color,
	secondary:     Color,
	secondary_var: Color,
	tertiary:      Color,
	tertiary_var:  Color,
	error:         Color,
	success:       Color,
}

// A mapping between color themes and actual ui elements.
// This level of indirection should provide some flexibility.
Element_Theme :: struct {}

Palette_Entry :: struct {
	s_300: Color,
	s_400: Color,
	s_500: Color,
	s_600: Color,
	s_700: Color,
	s_800: Color,
	s_900: Color,
}

Palette :: struct {
	primary:   Palette_Entry,
	secondary: Palette_Entry,
	tertiary:  Palette_Entry,
	// quarternary: Palette_Entry,
	grey:      Palette_Entry, // ranges from nearly white to nearly black
}

palette := Palette {
	primary = Palette_Entry {
		s_300 = Color{0.88, 0.94, 0.99, 1.0}, // #E0E2FC
		s_400 = Color{0.70, 0.75, 0.97, 1.0}, // #B2B7F7
		s_500 = Color{0.51, 0.56, 0.95, 1.0}, // #828DF2
		s_600 = Color{0.30, 0.38, 0.92, 1.0}, // #4D62EB
		s_700 = Color{0.14, 0.25, 0.99, 1.0}, // #243FBD
		s_800 = Color{0.07, 0.15, 0.46, 1.0}, // #132476
		s_900 = Color{0.02, 0.05, 0.20, 1.0}, // #040B34
	},
	secondary = Palette_Entry {
		s_300 = Color{0.95, 1.00, 0.98, 1.0}, // #F2EFFB
		s_400 = Color{0.84, 0.79, 0.95, 1.0}, // #D6CBF3
		s_500 = Color{0.72, 0.61, 0.91, 1.0}, // #B699E9
		s_600 = Color{0.59, 0.43, 0.93, 1.0}, // #976EDE
		s_700 = Color{0.48, 0.25, 0.78, 1.0}, // #793FC8
		s_800 = Color{0.31, 0.15, 0.53, 1.0}, // #502787
		s_900 = Color{0.16, 0.08, 0.29, 1.0}, // #2A124B
	},
	tertiary = Palette_Entry {
		s_300 = Color{0.99, 0.86, 0.88, 1.0}, // #F3DBE1
		s_400 = Color{0.90, 0.67, 0.73, 1.0}, // #E6A9B9
		s_500 = Color{0.86, 0.45, 0.57, 1.0}, // #DB7292
		s_600 = Color{0.72, 0.38, 0.53, 1.0}, // #B6486D
		s_700 = Color{0.50, 0.19, 0.29, 1.0}, // #80304B
		s_800 = Color{0.31, 0.09, 0.17, 1.0}, // #4E1A2C
		s_900 = Color{0.14, 0.03, 0.07, 1.0}, // #230811
	},
	grey = Palette_Entry {
		s_300 = Color{0.94, 0.94, 0.95, 1.0}, // #F0F0F1
		s_400 = Color{0.78, 0.78, 0.80, 1.0}, // #C7C8CB
		s_500 = Color{0.62, 0.61, 0.65, 1.0}, // #9FA1A6
		s_600 = Color{0.48, 0.49, 0.51, 1.0}, // #7A7C82
		s_700 = Color{0.34, 0.35, 0.36, 1.0}, // #57595D
		s_800 = Color{0.22, 0.22, 0.23, 1.0}, // #37383B
		s_900 = Color{0.10, 0.10, 0.11, 1.0}, // #191A1C
	},
}

hsla_to_rgba :: proc(h, s, l, a: f32) -> Color {
	h_norm: f32 = (math.mod_f32(h, 360)) / 60.0
	c: f32 = (1.0 - abs(2.0 * l - 1.0)) * s
	x: f32 = c * (1.0 - abs(math.mod(h_norm, 2.0) - 1.0))
	m: f32 = l - c / 2.0
	r, g, b: f32
	if h_norm < 1.0 {
		r = c;g = x;b = 0.0
	} else if h_norm < 2.0 {
		r = x;g = c;b = 0.0
	} else if h_norm < 3.0 {
		r = 0.0;g = c;b = x
	} else if h_norm < 4.0 {
		r = 0.0;g = x;b = c
	} else if h_norm < 5.0 {
		r = x;g = 0.0;b = c
	} else {
		r = c;g = 0.0;b = x
	}
	result := Color{r + m, g + m, b + m, a}
	return result
}
