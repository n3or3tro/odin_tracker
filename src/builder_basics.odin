// Builder basics, buttons, containers, etc.
package main

Text_Box_Signals :: struct {
	box_signals: Box_Signals,
	text:        string,
}
Draggable_Container_Signals :: struct {
	handle_bar: Box_Signals,
	container:  Box_Signals,
}

container :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache({.Draw}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

draggable_container :: proc(id_string: string, rect: ^Rect) -> Draggable_Container_Signals {
	handle_bar_rect := cut_rect(rect, RectCut{side = .Top, size = {.Percent, 0.1}})
	handle_bar := text_button(tprintf("drag-me@{}-handle-bar", id_string), handle_bar_rect)
	b := box_from_cache({.Floating_X, .Draw}, id_string, rect^)
	append(&ui_state.temp_boxes, b)
	return Draggable_Container_Signals{handle_bar = handle_bar, container = box_signals(b)}
}

text_container :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache({.Draw, .Draw_Text}, id_string, rect)
	b.color = {1, 1, 1, 1}
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

button :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache({.Draw, .Clickable, .Active_Animation, .Hot_Animation}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

text_button :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache({.Draw, .Clickable, .Active_Animation, .Draw_Text, .Hot_Animation}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}


text_box :: proc(id_string: string, rect: Rect) -> Text_Box_Signals {
	data: string // might need to allocte this.
	b := box_from_cache({.Draw, .Clickable, .Draw_Text, .Active_Animation, .Edit_Text}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return {box_signals(b), data}
}
