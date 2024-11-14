package main

track :: proc(size: [2]Size) -> Box_Signals {
	t := box_from_cache({.Clickable, .Draw, .Hot_Animation}, "tracker_track", size)
	append(&ui_state.temp_boxes, t)
	draw_text("fuck yeah", 100, 100)
	return box_signals(t)
}
