package main


// Knob_Signals :: struct {
// 	rotation: i8,
// }

// rect will be a bounding box the knob circle is bound by.
knob :: proc(id_string: string, rect: ^Rect) -> Box_Signals {
	// outer part of the knob
	name := get_name_from_id_string(id_string)
	id := get_id_from_id_string(id_string)
	text := text_container(tprintf("{}@{}-heading", name, id), cut_top(rect, {.Percent, 0.1}))
	squared_rect := rect_to_square(rect^)
	text_height := rect_height(text.box.rect)
	squared_rect.top_left.y += text_height
	squared_rect.bottom_right.y += text_height
	knob_body := box_from_cache(
		{.Draw, .Clickable, .Scrollable},
		tprintf("knob-body@{}-knob-body", id),
		squared_rect,
	)
	append(&ui_state.temp_boxes, knob_body)

	// indicator line of the knob.	
	// indicator_center := (rect.top_left + rect.bottom_right) / 2

	return box_signals(knob_body)
}
