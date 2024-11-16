package main

button :: proc(id_string: string, rect: Rect) -> Box_Signals {
	// rect := cut_rect(top_rect(), rect_cut)
	b := box_from_cache({.Draw, .Clickable, .Active_Animation, .Draw_Text}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}
