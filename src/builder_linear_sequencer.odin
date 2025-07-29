package main

linear_sequencing_panel :: proc() {
	track_height: u32 = 120
	for i in 0 ..< app.n_tracks {
		if !app.tracks[i] {continue}
		create_linear_track(u32(i), track_height)
		spacer("spacer@spacer", RectCut{Size{.Pixels, f32(10)}, .Top})
	}
}

linear_track_container :: proc(id_string: string, rect: Rect, metadata: Box_Metadata = {}) -> Box_Signals {
	b := box_from_cache({.Clickable, .Draw}, id_string, rect, metadata = metadata)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

create_linear_track :: proc(which: u32, track_height: u32) {
	rect := cut_rect(top_rect(), RectCut{{.Pixels, f32(track_height)}, .Top})
	if which % 2 == 0 {
		push_color(palette.primary.s_600)
	} else {
		push_color(palette.primary.s_400)
	}
	linear_track_container(tprintf("@horizontal-track-{}", which), rect)
	clear_color_stack()
}
