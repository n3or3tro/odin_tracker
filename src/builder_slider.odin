package main
import "core:fmt"
import "core:strings"

Slider_Signals :: struct {
	value:         f32,
	max:           f32,
	grip_signals:  Box_Signals,
	track_signals: Box_Signals,
}

TRACK_WIDTH :: 0.4
TRACK_HEIGHT :: 0.8
GRIP_WIDTH :: 1.0
GRIP_HEIGHT :: 0.07

// will return in pixels for now.
calc_grip_height :: proc(value, max: f32, track_height: f32) -> f32 {
	return (value / max) * track_height
}

slider :: proc(
	ui_state: ^UI_State,
	size: [2]Size,
	text: string,
	value: f32,
	max: f32,
) -> Slider_Signals {

	bounding_box := box_from_cache({}, ui_state, text, size)
	bounding_box.child_layout_axis = .Y
	layout_push_parent(&ui_state.layout_stack, bounding_box)

	track_container := box_from_cache(
		{},
		ui_state,
		fmt.aprintf("%s%s", text, "_track_container"),
		{
			{kind = .Pecent_Of_Parent, value = 1.0},
			{kind = .Pecent_Of_Parent, value = TRACK_HEIGHT},
		},
	)
	track_container.child_layout_axis = .X
	layout_push_parent(&ui_state.layout_stack, track_container)

	x_space(ui_state, 0.3, fmt.aprintf("%s%s", text, "__space1"))
	track_size: [2]Size = {
		Size{kind = .Pecent_Of_Parent, value = TRACK_WIDTH},
		Size{kind = .Pecent_Of_Parent, value = 1},
	}
	track_id: string = fmt.aprintf("%s%s", text, "_track")
	slider_track := box_from_cache({.Scrollable, .Draw}, ui_state, track_id, track_size)
	x_space(ui_state, 0.3, fmt.aprintf("%s%s", text, "__space2"))

	layout_pop_parent(&ui_state.layout_stack)

	grip_size: [2]Size = {
		Size{kind = .Pecent_Of_Parent, value = GRIP_WIDTH},
		Size{kind = .Pecent_Of_Parent, value = GRIP_HEIGHT},
	}
	grip_id: string = fmt.aprintf("%s%s", text, "_grip")
	slider_grip := box_from_cache(
		{
			.Clickable,
			.Hot_Animation,
			.Scrollable,
			.Active_Animation,
			.Draggable,
			.Draw,
			.No_Offset,
		},
		ui_state,
		grip_id,
		grip_size,
	)

	slider_grip.calc_rel_pos = {0, calc_grip_height(value, max, slider_track.calc_size.y)}

	append(&ui_state.temp_boxes, slider_track)
	append(&ui_state.temp_boxes, slider_grip)
	layout_pop_parent(&ui_state.layout_stack)
	return Slider_Signals {
		grip_signals = box_signals(ui_state^, slider_grip),
		track_signals = box_signals(ui_state^, slider_track),
		value = value,
		max = max,
	}
}
