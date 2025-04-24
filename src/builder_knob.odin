package main


Knob_Signals :: struct {
	rotation: i8,
}

// // rect will be a bounding box the knob circle is bound by.
// knob :: proc(id_string: string, rect: Rect) {
// 	handle_bar_rect := cut_rect(rect, RectCut{side = .Top, size = {.Percent, 0.1}})
// 	handle_bar := text_button(tprintf("drag-me@{}-handle-bar", id_string), handle_bar_rect)
// 	b := box_from_cache({.Floating_X, .Draw}, id_string, rect^)
// 	append(&ui_state.temp_boxes, b)
// 	return Draggable_Container_Signals{handle_bar = handle_bar, container = box_signals(b)}
// }
