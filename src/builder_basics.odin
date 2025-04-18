// Builder basics, buttons, containers, etc.
package main

Text_Box_Signals :: struct {
	box_signals: Box_Signals,
	text:        string,
}

container :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache({.Draw, .Draggable}, id_string, rect)
	append(&ui_state.temp_boxes.first_layer, b)
	return box_signals(b)
}
text_container :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache({.Draw, .Draw_Text}, id_string, rect)
	b.color = {1, 1, 1, 1}
	append(&ui_state.temp_boxes.first_layer, b)
	return box_signals(b)
}

button :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache({.Draw, .Clickable, .Active_Animation, .Hot_Animation}, id_string, rect)
	if ui_state.z_layer == .second {
		append(&ui_state.temp_boxes.second_layer, b)
	} else {
		append(&ui_state.temp_boxes.first_layer, b)
	}
	return box_signals(b)
}

text_button :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache(
		{.Draw, .Clickable, .Active_Animation, .Draw_Text, .Hot_Animation},
		id_string,
		rect,
	)
	if ui_state.z_layer == .second {
		printf("%s is on the second layer", id_string)
		append(&ui_state.temp_boxes.second_layer, b)
	} else {
		append(&ui_state.temp_boxes.first_layer, b)
	}
	return box_signals(b)
}


text_box :: proc(id_string: string, rect: Rect) -> Text_Box_Signals {
	data: string // might need to allocte this.
	b := box_from_cache(
		{.Draw, .Clickable, .Draw_Text, .Active_Animation, .Edit_Text},
		id_string,
		rect,
	)

	if ui_state.z_layer == .second {
		append(&ui_state.temp_boxes.second_layer, b)
	} else {
		append(&ui_state.temp_boxes.first_layer, b)
	}
	return {box_signals(b), data}
}
