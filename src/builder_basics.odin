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
	b := box_from_cache({.Draw_Text}, id_string, rect)
	b.color = {1, 1, 1, 1}
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

// Lets you draw a text container at an absolute x,y position and calculates size
// based on the font.
text_container_absolute :: proc(id_string: string, x, y: f32) -> Box_Signals {
	name := get_name_from_id_string(id_string)
	length := f32(word_rendered_length(name))
	height := f32(tallest_char_height(name))
	rect := Rect{{x, y}, {x + length, y + height}}
	b := box_from_cache({.Draw_Text}, id_string, rect)
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
	b := box_from_cache(
		{.Draw, .Clickable, .Active_Animation, .Draw_Text, .Hot_Animation},
		id_string,
		rect,
	)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

// Same as text_container_absolute, but for text buttons.
text_button_absolute :: proc(id_string: string, x, y: f32) -> Box_Signals {
	name := get_name_from_id_string(id_string)
	length := f32(word_rendered_length(name))
	height := f32(tallest_char_height(name))
	rect := Rect{{x, y}, {x + length, y + height}}
	b := box_from_cache(
		{.Draw, .Clickable, .Active_Animation, .Draw_Text, .Hot_Animation},
		id_string,
		rect,
	)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

// Differs from text_container as it's like <input> element from HTML.
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
