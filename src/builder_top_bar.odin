package main
import sdl "vendor:sdl2"
Top_Bar_Signals :: struct {
	play:     Box_Signals,
	restart:  Box_Signals,
	settings: Box_Signals,
	sampler:  Box_Signals,
	tabs:     [3]Box_Signals,
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
	sampler_rect := cut_left(&top_bar_rect, Size{.Pixels, button_width})
	settings_rect := cut_right(&top_bar_rect, Size{.Pixels, button_width})
	tabs_rect := shrink_x(top_bar_rect, Size{kind = .Percent, value = 0.05})
	tab0_rect := cut_left(&tabs_rect, {.Percent, 0.33})
	tab1_rect := get_left(tabs_rect, {.Percent, 0.50})
	tab2_rect := get_right(tabs_rect, {.Percent, 0.50})

	push_color(palette.secondary.s_800)
	play_button := text_button(app.audio_state.playing ? ":)@topbar_play" : ":(@topbar_pause", play_rect)
	push_color(palette.secondary.s_600)
	settings_button := text_button("Settngs@settings-button-topbar", settings_rect)
	push_color(palette.secondary.s_400)
	sampler_button := text_button("Open Sampler@sampler-button-topbar", sampler_rect)
	push_color(palette.secondary.s_300)
	restart_button := text_button("Restart@restart-button-topbar", restart_rect)

	// push_color(palette.secondary.s_300)
	// reset_data_rect := rest
	// reset_data_button := text_button("Reset Data@reset-data-button-topbar")

	push_color(palette.tertiary.s_700)
	tab0_button := text_button("Tab 0 @tab0-button-top-bar", tab0_rect)
	tab1_button := text_button("Tab 1 @tab1-button-top-bar", tab1_rect)
	tab2_button := text_button("Tab 2 @tab2-button-top-bar", tab2_rect)
	clear_color_stack()

	return Top_Bar_Signals {
		play = play_button,
		restart = restart_button,
		settings = settings_button,
		sampler = sampler_button,
		tabs = {tab0_button, tab1_button, tab2_button},
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
		for &track in app.audio_state.tracks {
			track.curr_step = 0
		}
	}
	if signals.settings.clicked {
		ui_state.settings_toggled = !ui_state.settings_toggled
	}
	if signals.play.clicked {
		app.audio_state.playing = !app.audio_state.playing
	}
	if signals.sampler.clicked {
		app.sampler_open = !app.sampler_open
	}
	if signals.tabs[0].clicked {
		app.active_tab = 0
	}
	if signals.tabs[1].clicked {
		app.active_tab = 1
	}
	if signals.tabs[2].clicked {
		app.active_tab = 2
	}
}

settings_menu :: proc(settings_menu_rect: Rect) -> Settings_Menu_Signals {
	n_buttons: f32 = 5.0
	padding := 0.01

	ui_state.z_index = 1
	defer ui_state.z_index = 0

	settings_container := container("options-container@settings-container-topbar", settings_menu_rect)

	resize_buttons_rect := get_top(settings_menu_rect, Size{kind = .Percent, value = 1 / n_buttons})
	reduce_rect := get_left(resize_buttons_rect, Size{.Percent, 0.5})
	increase_rect := get_right(resize_buttons_rect, Size{.Percent, 0.5})

	reduce_button := text_button("-@zoomout-button-topbar", reduce_rect)
	increase_button := text_button("+@zoomein-button-topbar", increase_rect)

	scratch_rect := resize_buttons_rect

	scratch_rect.bottom_right.y += rect_height(resize_buttons_rect)
	scratch_rect.top_left.y += rect_height(resize_buttons_rect)
	b1 := text_button("test@setting-button-1", scratch_rect)

	scratch_rect.bottom_right.y += rect_height(resize_buttons_rect)
	scratch_rect.top_left.y += rect_height(resize_buttons_rect)
	b2 := text_button("test2@settings-button-2", scratch_rect)

	scratch_rect.bottom_right.y += rect_height(resize_buttons_rect)
	scratch_rect.top_left.y += rect_height(resize_buttons_rect)
	b3 := text_button("test3@settings-button-3", scratch_rect)

	scratch_rect.bottom_right.y += rect_height(resize_buttons_rect)
	scratch_rect.top_left.y += rect_height(resize_buttons_rect)
	b4 := text_button("test4@settings-button-4", scratch_rect)
	return Settings_Menu_Signals{grow_ui = increase_button, shrink_ui = reduce_button}
}
