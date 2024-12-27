package main
import "core:fmt"
import "core:sys/posix"
import thread "core:thread"
import nfd "third_party/nativefiledialog"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

UI_State :: struct {
	window:      ^sdl.Window,
	mouse:       struct {
		pos:           [2]i32,
		left_pressed:  bool,
		right_pressed: bool,
		wheel:         [2]i8, //-1 moved down, +1 move up
	},
	// layout_stack:  Layout_Stack,
	box_cache:   Box_Cache, // cross-frame cache of boxes
	char_map:    map[rune]Character,
	temp_boxes:  [dynamic]^Box, // store boxes so we can access them when rendering
	first_frame: bool, // dont want to render on the first frame
	// used to determine the top rect which rect cuts are taken from
	rect_stack:  [dynamic]^Rect,
}

Top_Bar_Signals :: struct {
	toggle_play:    Box_Signals,
	toggle_explore: Box_Signals,
}


top_bar :: proc() {
	top_bar_rect := cut_top(top_rect(), Size{kind = .Percent, value = 0.03})
	play_space := get_left(top_bar_rect, Size{kind = .Percent, value = 0.45})
	stop_space := get_right(top_bar_rect, Size{kind = .Percent, value = 0.45})

	play_button := get_right(play_space, Size{kind = .Percent, value = 0.5})
	stop_button := get_left(stop_space, Size{kind = .Percent, value = 0.5})
	toggle_play := button("lol@yourmum", play_button)
	toggle_explore := button("lolwhat@yourmum", stop_button)
	if toggle_play.clicked {
		audio_state.playing = !audio_state.playing
		toggle_all_audio_playing()
	}
}

create_ui :: proc() {
	top_bar()
	track_padding: u32 = 10
	track_width: f32 = f32(wx^ / i32(N_TRACKS)) - f32(track_padding)
	for i in 0 ..= 9 {
		create_track(u32(i), track_width)
		spacer(
			fmt.aprintf("track_spacer%s@1", i, allocator = context.temp_allocator),
			RectCut{Size{.Pixels, f32(track_padding)}, .Left},
		)
	}
}

render_ui :: proc() {
	if !ui_state.first_frame {
		rect_rendering_data := get_box_rendering_data()
		defer delete_dynamic_array(rect_rendering_data^)
		n_rects := u32(len(rect_rendering_data))
		populate_vbuffer_with_rects(
			quad_vabuffer,
			0,
			raw_data(rect_rendering_data^),
			n_rects * size_of(Rect_Render_Data),
		)
		gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, i32(n_rects))
	}
}
