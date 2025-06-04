package main


// Knob_Signals :: struct {
// 	rotation: i8,
// }

// rect will be a bounding box the knob circle is bound by.
knob :: proc(id_string: string, rect: Rect) -> Box_Signals {
	// outer part of the knob
	knob_body := box_from_cache(
		{.Draw, .Clickable, .Scrollable},
		tprintf("knob-body@{}-knob-body", id_string),
		rect,
	)
	append(&ui_state.temp_boxes, knob_body)

	// indicator line of the knob.	
	// indicator_center := (rect.top_left + rect.bottom_right) / 2

	return box_signals(knob_body)
}
