package main


Knob_Signals :: struct {
	rotation: i8,
}

// rect will be a bounding box the knob circle is bound by.
knob :: proc(id_string: string, rect: Rect) {
	knob_body := container(tprintf("knob-body@{}-knob-body", id_string), rect)
	// append(&ui_state.temp_boxes, b)
	// return Knob_Signals { 
	// 	rotation = 
	// }
}
