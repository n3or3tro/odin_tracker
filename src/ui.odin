package main
import "core:fmt"
import "core:sys/posix"
import thread "core:thread"
import nfd "third_party/nativefiledialog"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

UI_State :: struct {
	window:        ^sdl.Window,
	mouse:         struct {
		pos:           [2]i32,
		left_pressed:  bool,
		right_pressed: bool,
		wheel:         [2]i8, //-1 moved down, +1 move up
	},
	// layout_stack:  Layout_Stack,
	box_cache:     Box_Cache, // cross-frame cache of boxes
	char_map:      map[rune]Character,
	temp_boxes:    [dynamic]^Box, // store boxes so we can access them when rendering
	first_frame:   bool, // dont want to render on the first frame
	window_width:  u32,
	window_height: u32,
	// used to determine the top rect which rect cuts are taken from
	rect_stack:    [dynamic]^Rect,
}

top_bar :: proc() {
	// draw top bar
	top_bar_rect := cut_top(top_rect(), Size{kind = .Percent, value = 0.03})
	top_bar_width := rect_width(top_bar_rect)
	cut_left(&top_bar_rect, Size{kind = .Pixels, value = top_bar_width * 0.9 / 2})
	cut_right(&top_bar_rect, Size{kind = .Pixels, value = top_bar_width * 0.9 / 2})
	play_button := get_left(top_bar_rect, Size{kind = .Percent, value = 0.5})
	stop_button := get_right(top_bar_rect, Size{kind = .Percent, value = 1})
	// play_button = shrink_x(play_button, Size{.Percent, 0.3})
	// stop_button = shrink_x(stop_button, Size{.Percent, 0.3})
	button("lol@yourmum", play_button)
	button("lolwhat@yourmum", stop_button)
}

file_dialog :: proc() {
	init_and_run :: proc() {
		nfd.Init()
		defer nfd.Quit()

		paths := make_multi_pointer([^]cstring, 50)
		path: cstring
		filters := [2]nfd.Filter_Item{{"Source code", "c,cpp,cc"}, {"Headers", "h,hpp"}}

		args := nfd.Open_Dialog_Args {
			// filter_list  = raw_data(filters[:]),
			// filter_count = len(filters),
			filter_list  = nil,
			filter_count = 0,
		}

		result := nfd.OpenDialogMultipleN(paths, nil, 0, nil)
		switch result {
		case .Okay:
			{
				fmt.println("Success!")
			}
		case .Cancel:
			fmt.println("User pressed cancel.")
		case .Error:
			fmt.println("Error:", nfd.GetError())
		}
	}
	thread.create_and_start(init_and_run)
}

create_ui :: proc() {
	track_padding: u32 = 10
	track_width: f32 = f32(wx^ / i32(n_tracks)) - f32(track_padding)
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
