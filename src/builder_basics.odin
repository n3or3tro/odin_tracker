// Builder basics, buttons, containers, etc.
package main

Text_Box_Signals :: struct {
	box_signals: Box_Signals,
	text:        string,
}

container :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache({.Draw}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

button :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache({.Draw, .Clickable, .Active_Animation, .Hot_Animation}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

text_button :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache(
		{.Draw, .Clickable, .Active_Animation, .Draw_Text, .Hot_Animation},
		id_string,
		rect,
	)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}


text_box :: proc(id_string: string, rect: Rect) -> Text_Box_Signals {
	data: string // might need to allocte this.
	b := box_from_cache(
		{.Draw, .Clickable, .Draw_Text, .Active_Animation, .Edit_Text},
		id_string,
		rect,
	)
	append(&ui_state.temp_boxes, b)
	return {box_signals(b), data}
}
