package main
import "core:fmt"
import alg "core:math/linalg"
import "core:sys/posix"
import thread "core:thread"
import nfd "third_party/nativefiledialog"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

Color :: [4]f32
UI_State :: struct {
	window:           ^sdl.Window,
	mouse:            struct {
		pos:           [2]i32,
		left_pressed:  bool,
		right_pressed: bool,
		wheel:         [2]i8, //-1 moved down, +1 move up
	},
	// layout_stack:  Layout_Stack,
	box_cache:        Box_Cache, // cross-frame cache of boxes
	char_map:         map[rune]Character,
	temp_boxes:       [dynamic]^Box, // store boxes so we can access them when rendering
	first_frame:      bool, // dont want to render on the first frame
	// used to determine the top rect which rect cuts are taken from
	rect_stack:       [dynamic]^Rect,
	settings_toggled: bool,
	// color_stack:      [dynamic]^Color,
	color_stack:      [dynamic]Color,
}
Top_Bar_Signals :: struct {
	play:     Box_Signals,
	// toggle:   Box_Signals,
	settings: Box_Signals,
}
Settings_Menu_Signals :: struct {
	grow_ui:   Box_Signals,
	shrink_ui: Box_Signals,
}


top_bar :: proc() -> Top_Bar_Signals {
	top_bar_rect := cut_top(top_rect(), Size{kind = .Percent, value = 0.03})

	play_space := get_left(top_bar_rect, Size{kind = .Percent, value = 0.45})
	stop_space := get_right(top_bar_rect, Size{kind = .Percent, value = 0.45})
	settings_space := get_right(top_bar_rect, Size{kind = .Percent, value = 0.10})

	play_button_rect := get_right(play_space, Size{kind = .Percent, value = 0.5})
	stop_button_rect := get_left(stop_space, Size{kind = .Percent, value = 0.5})

	settings_button := text_button("Settings@topbar", settings_space)
	play_button := text_button("Play@topbar", play_button_rect)
	explore_button := text_button("Explore@topbar", stop_button_rect)
	return Top_Bar_Signals{play = play_button, settings = settings_button}
}

handle_top_bar_interactions :: proc(signals: Top_Bar_Signals) {
	if signals.settings.clicked {
		ui_state.settings_toggled = !ui_state.settings_toggled
	}
	if ui_state.settings_toggled {
		settings_space := signals.settings.box.rect
		// A litle janky, hardcoded way to figure out how big the settings
		// box is going to be.
		settings_window_rect := Rect {
			top_left     = {
				settings_space.top_left.x,
				settings_space.top_left.y + rect_height(settings_space),
			},
			bottom_right = {
				settings_space.bottom_right.x,
				settings_space.bottom_right.y + rect_height(settings_space) * 7,
			},
		}
		settings_container := container("Options-Container@topbar", settings_window_rect)
		settings := settings_menu(settings_container.box.rect)
		if settings.grow_ui.clicked {
			println("growing")
			ui_scale += 0.1
			wx^ = i32(WINDOW_WIDTH * ui_scale)
			wy^ = i32(WINDOW_HEIGHT * ui_scale)
			sdl.SetWindowSize(window, wx^, wy^)
			set_shader_vec2(quad_shader_program, "screen_res", {f32(wx^), f32(wy^)})
		}
		if settings.shrink_ui.clicked {
			println("shrinkgin")
			ui_scale -= 0.1
			wx^ = i32(WINDOW_WIDTH * ui_scale)
			wy^ = i32(WINDOW_HEIGHT * ui_scale)

		}
	}
	if signals.play.clicked {
		audio_state.playing = !audio_state.playing
		toggle_all_audio_playing()
	}

}
settings_menu :: proc(settings_menu_rect: Rect) -> Settings_Menu_Signals {
	n_buttons: f32 = 5.0
	padding := 0.01
	resize_rect := get_top(settings_menu_rect, Size{kind = .Percent, value = 1 / n_buttons})
	reduce := get_left(resize_rect, Size{.Percent, 0.5})
	increase := get_right(resize_rect, Size{.Percent, 0.5})
	reduce_button := text_button("-@topbar", reduce)
	increase_button := text_button("+@topbar", increase)
	return Settings_Menu_Signals{grow_ui = increase_button, shrink_ui = reduce_button}
}

create_ui :: proc() {
	topbar := top_bar()
	track_padding: u32 = 3
	track_width: f32 = f32(wx^ / i32(N_TRACKS)) - f32(track_padding)
	for i in 0 ..= 9 {
		create_track(u32(i), track_width)
		push_color({0, 0, 0, 1})
		spacer(
			fmt.aprintf("track_spacer%s@1", i, allocator = context.temp_allocator),
			RectCut{Size{.Pixels, f32(track_padding)}, .Left},
		)
		pop_color()
	}
	handle_top_bar_interactions(topbar)
}

render_ui :: proc() {
	if !ui_state.first_frame {
		// setup_for_quads(&quad_shader_program)
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
