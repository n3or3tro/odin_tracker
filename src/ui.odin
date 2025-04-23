package main
import "core:fmt"
import alg "core:math/linalg"
import "core:sys/posix"
import thread "core:thread"
import gl "vendor:OpenGL"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"

Color :: [4]f32
Z_Layer :: enum {
	default,
	first,
	second,
}

UI_State :: struct {
	box_cache:           Box_Cache, // cross-frame cache of boxes
	atlas_metadata:      Atlas_Metadata,
	temp_boxes:          [dynamic]^Box,
	first_frame:         bool, // dont want to render on the first frame
	rect_stack:          [dynamic]^Rect,
	settings_toggled:    bool,
	color_stack:         [dynamic]Color,
	selected_steps:      [N_TRACKS][32]bool,
	step_pitches:        [N_TRACKS][32]f32,
	ui_scale:            f32, // between 0.0 and 1.0.
	// Used to tell the core layer to override some value
	// of a box that's in the cache. Useful for parts of the code
	// where the box isn't easilly accessible (like in audio related stuff).
	override_color:      bool,
	quad_vbuffer:        ^u32,
	quad_vabuffer:       ^u32,
	quad_shader_program: u32,
	root_rect:           ^Rect,
	frame_num:           ^u64,
	// hot_id:              string,
	// active_id:           string,
	hot_box:             ^Box,
	active_box:          ^Box,
	z_index:             u8,
	context_menu_pos:    Vec2,
	context_menu_active: bool,
	right_clicked_on:    ^Box,
	wav_rendering_data:  map[ma.sound][dynamic]Rect_Render_Data,
}

num_column :: proc(track_height: u32, n_steps: u32) {
	num_col_rect := cut_rect(top_rect(), {{.Percent, track_steps_width_ratio}, .Left})
	step_height := f32(track_height) / f32(n_steps)
	for i in 0 ..< n_steps {
		curr_step := cut_top(&num_col_rect, {.Pixels, step_height})
		text_container(tprintf("{}:@number_column", i), curr_step)
	}
}

track_steps_height_ratio: f32 = 0.75
track_steps_width_ratio: f32 = 0.04
n_track_steps: u32 = 32

create_ui :: proc() {
	topbar := top_bar()
	col_height := cast(u32)(rect_height(top_rect()^) * track_steps_height_ratio)
	num_column(col_height, n_track_steps)
	track_padding: u32 = 3
	// This is the remaining space to the right of the number column.
	rest_screen := f32(app.wx^) * (1 - track_steps_width_ratio)
	track_width: f32 = f32(rest_screen / f32(N_TRACKS) - f32(track_padding))
	for i in 0 ..< app.n_tracks {
		create_track(u32(i), track_width)
		push_color({0, 0, 0, 1})
		spacer(tprintf("track_spacer_{}@1", i), RectCut{Size{.Pixels, f32(track_padding)}, .Left})
		pop_color()
	}
	add_track_rect := Rect {
		top_left     = {track_width * f32(app.n_tracks) + 100, f32(app.wy^ / 2) - 50},
		bottom_right = {track_width * f32(app.n_tracks) + 150, f32(app.wy^ / 2)},
	}
	ui_state.z_index = 5
	add_track := text_button("+@add_track", add_track_rect)
	ui_state.z_index = 0
	if add_track.clicked {
		app.n_tracks += 1
	}
	handle_top_bar_interactions(topbar)
	if app.sampler_open {
		sampler_top_left := app.sampler_pos
		sampler_bottom_right := Vec2{1000 + sampler_top_left.x, 500 + sampler_top_left.y}
		sampler_signals := sampler("first-sampler@1", &Rect{sampler_top_left, sampler_bottom_right})
		if sampler_signals.container_signals.handle_bar.dragging {
			app.dragging_window = true
		}
		if app.dragging_window {
			change_in_x := app.mouse.last_pos.x - app.mouse.pos.x
			change_in_y := app.mouse.last_pos.y - app.mouse.pos.y
			app.sampler_pos.x -= f32(change_in_x)
			app.sampler_pos.y -= f32(change_in_y)
		}
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
	populate_vbuffer_with_rects(ui_state.quad_vabuffer, 0, raw_data(rect_rendering_data^), n_rects * size_of(Rect_Render_Data))
	gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, i32(n_rects))

	delete_dynamic_array(rect_rendering_data^)
	reset_ui_state()
}

reset_ui_state :: proc() {
	ui_state.active_box = nil
	ui_state.hot_box = nil
}
