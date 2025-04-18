package main
import sdl "vendor:sdl2"
Top_Bar_Signals :: struct {
	play:     Box_Signals,
	restart:  Box_Signals,
	settings: Box_Signals,
}

Settings_Menu_Signals :: struct {
	grow_ui:   Box_Signals,
	shrink_ui: Box_Signals,
}

top_bar :: proc() -> Top_Bar_Signals {
	top_bar_rect := cut_top(top_rect(), Size{kind = .Percent, value = 0.03})
	button_width := rect_width(get_left(top_bar_rect, Size{kind = .Percent, value = 0.1}))

	play_rect := cut_left(&top_bar_rect, Size{.Pixels, button_width})
	restart_rect := cut_left(&top_bar_rect, Size{.Pixels, button_width})
	settings_rect := get_right(top_bar_rect, Size{.Pixels, button_width})


	settings_button := text_button("Settings@topbar", settings_rect)
	play_button := text_button(app.audio_state.playing ? ":(@topbar" : ":)@topbar", play_rect)
	restart_button := text_button("Restart@topbar", restart_rect)
	return Top_Bar_Signals {
		play = play_button,
		restart = restart_button,
		settings = settings_button,
	}
}

handle_top_bar_interactions :: proc(signals: Top_Bar_Signals) {
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
		settings := settings_menu(settings_window_rect)
		if settings.grow_ui.clicked {
		}
		if settings.shrink_ui.clicked {
		}
	}
	if signals.restart.clicked {
		app.audio_state.curr_step = 0
	}
	if signals.settings.clicked {
		ui_state.settings_toggled = !ui_state.settings_toggled
	}

	if signals.play.clicked {
		// toggle_all_audio_playing()
		app.audio_state.playing = !app.audio_state.playing
		// if audio_state.playing {
		// 	start_all_audio()
		// } else {
		// 	stop_all_audio()
		// }
	}

}

settings_menu :: proc(settings_menu_rect: Rect) -> Settings_Menu_Signals {
	n_buttons: f32 = 5.0
	padding := 0.01

	ui_state.z_layer = .second

	settings_container := container("Options-Container@topbar", settings_menu_rect)

	resize_buttons_rect := get_top(
		settings_menu_rect,
		Size{kind = .Percent, value = 1 / n_buttons},
	)
	reduce_rect := get_left(resize_buttons_rect, Size{.Percent, 0.5})
	increase_rect := get_right(resize_buttons_rect, Size{.Percent, 0.5})

	reduce_button := text_button("-@topbar", reduce_rect)
	increase_button := text_button("+@topbar", increase_rect)

	scratch_rect := resize_buttons_rect

	scratch_rect.bottom_right.y += rect_height(resize_buttons_rect)
	scratch_rect.top_left.y += rect_height(resize_buttons_rect)
	b1 := text_button("test@topbar", scratch_rect)

	scratch_rect.bottom_right.y += rect_height(resize_buttons_rect)
	scratch_rect.top_left.y += rect_height(resize_buttons_rect)
	b2 := text_button("test2@topbar", scratch_rect)

	scratch_rect.bottom_right.y += rect_height(resize_buttons_rect)
	scratch_rect.top_left.y += rect_height(resize_buttons_rect)
	b3 := text_button("test3@topbar", scratch_rect)

	scratch_rect.bottom_right.y += rect_height(resize_buttons_rect)
	scratch_rect.top_left.y += rect_height(resize_buttons_rect)
	b4 := text_button("test4@topbar", scratch_rect)
	ui_state.z_layer = .default
	return Settings_Menu_Signals{grow_ui = increase_button, shrink_ui = reduce_button}
}
