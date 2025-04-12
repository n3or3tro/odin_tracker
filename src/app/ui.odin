package app
import nfd "../third_party/nativefiledialog"
import "core:fmt"
import alg "core:math/linalg"
import "core:sys/posix"
import thread "core:thread"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

Color :: [4]f32
UI_State :: struct {
	// layout_stack:  Layout_Stack,
	box_cache:           Box_Cache, // cross-frame cache of boxes
	char_map:            map[rune]Character,
	temp_boxes:          [dynamic]^Box, // store boxes so we can access them when rendering
	first_frame:         bool, // dont want to render on the first frame
	// used to determine the top rect which rect cuts are taken from
	rect_stack:          [dynamic]^Rect,
	settings_toggled:    bool,
	// color_stack:      [dynamic]^Color,
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
	text_shader_program: u32,
	text_vbuffer:        ^u32,
	text_vabuffer:       ^u32,
	root_rect:           ^Rect,
	frame_num:           ^u64,
}

num_column :: proc(track_height: u32, n_steps: u32) {
	num_col_rect := cut_rect(top_rect(), {{.Percent, track_steps_width_ratio}, .Left})
	step_height := f32(track_height) / f32(n_steps)
	for i in 0 ..< n_steps {
		curr_step := cut_top(&num_col_rect, {.Pixels, step_height})
		text_container(
			aprintf("%d:@number_column", i, allocator = context.temp_allocator),
			curr_step,
		)
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
	for i in 0 ..= 9 {
		create_track(u32(i), track_width)
		push_color({0, 0, 0, 1})
		spacer(
			aprintf("track_spacer%s@1", i, allocator = context.temp_allocator),
			RectCut{Size{.Pixels, f32(track_padding)}, .Left},
		)
		pop_color()
	}
	handle_top_bar_interactions(topbar)
	sampler("first-sampler", Rect{top_left = {100, 100}, bottom_right = {2000, 500}})
}

render_ui :: proc() {
	if !ui_state.first_frame {
		rect_rendering_data := get_all_rendering_data()
		defer delete_dynamic_array(rect_rendering_data^)
		n_rects := u32(len(rect_rendering_data))
		populate_vbuffer_with_rects(
			ui_state.quad_vabuffer,
			0,
			raw_data(rect_rendering_data^),
			n_rects * size_of(Rect_Render_Data),
		)
		gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, i32(n_rects))
	}
}


main_color: Color = {0.6, 0.5, 0.9, 1}
second_color: Color = {0.3, 0.2, 0.6, 1}
third_color: Color = {0.5, 0.9, 0.2, 1}
fourth_color: Color = {0.5, 0.65, 0.1, 1}
accent_color: Color = {0.9, 0.8, 1, 1}

// main_color: Color = {0.5, 0.5, 0.5, 255}
// second_color: Color = {1, 89, 88, 255}
// third_color: Color = {0, 143, 140, 255}
// fourth_color: Color = {12, 171, 168, 255}
// accent_color: Color = {15, 194, 192, 255}
map_colors :: proc() {
	for i in 0 ..< 4 {
		main_color[i] = map_range(0, 255, 0, 1, main_color[i])
		second_color[i] = map_range(0, 255, 0, 1, second_color[i])
		third_color[i] = map_range(0, 255, 0, 1, third_color[i])
		fourth_color[i] = map_range(0, 255, 0, 1, fourth_color[i])
		accent_color[i] = map_range(0, 255, 0, 1, accent_color[i])
	}
}
