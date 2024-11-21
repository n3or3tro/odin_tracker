package main
import "core:crypto/hash"
import "core:fmt"
import "core:strings"

Track_Button_Signals :: struct {
	play_signals:      Box_Signals,
	file_load_signals: Box_Signals,
}
Track_Control_Signals :: struct {
	value:          f32,
	max:            f32,
	grip_signals:   Box_Signals,
	track_signals:  Box_Signals,
	button_signals: Track_Button_Signals,
}

// assumes 0 <= value <= 100
track_controls :: proc(id_string: string, rect: ^Rect, value: f32) -> Track_Control_Signals {

	cut_rect(rect, {Size{.Percent, 0.33}, .Left})
	buttons_rect := cut_rect(rect, {Size{.Percent, 0.1}, .Bottom})
	play_button_rect := get_rect(&buttons_rect, {Size{.Percent, 0.4}, .Left})
	play_button := button(
		fmt.aprintf("%s_play_button@1", get_name_from_id_string(id_string)),
		play_button_rect,
	)
	file_load_button_rect := get_rect(&buttons_rect, {Size{.Percent, 0.4}, .Right})
	file_load_button := button(
		fmt.aprintf("%s_file_load_button@1", get_name_from_id_string(id_string)),
		file_load_button_rect,
	)

	cut_right(&play_button.box.rect, Size{.Percent, 0.5})
	cut_top(&play_button.box.rect, Size{.Percent, 0.4})
	play_button.box.rect = expand(play_button.box.rect, Size{.Percent, 0.4})

	slider_track_rect := cut_rect(rect, RectCut{Size{.Percent, 0.5}, .Left})
	slider_track := box_from_cache({.Scrollable, .Draw}, id_string, slider_track_rect)
	append(&ui_state.temp_boxes, slider_track)

	slider_grip_rect := get_bottom(&slider_track.rect, Size{.Pixels, 30})
	slider_grip_rect = expand_x(slider_grip_rect, Size{.Percent, 0.5})

	space_below_grip := get_bottom(&slider_track_rect, Size{.Percent, value / 100})
	slider_grip_rect.bottom_right.y -= (value / 100) * rect_height(slider_track_rect)
	slider_grip_rect.top_left.y -= (value / 100) * rect_height(slider_track_rect)
	slider_grip := box_from_cache(
		{.Clickable, .Hot_Animation, .Active_Animation, .Draggable, .Draw},
		fmt.aprintf(
			"%s%s@%s",
			get_name_from_id_string(id_string),
			"_grip",
			get_id_from_id_string(id_string),
		),
		slider_grip_rect,
	)
	append(&ui_state.temp_boxes, slider_grip)

	return Track_Control_Signals {
		value = value,
		max = 100,
		grip_signals = box_signals(slider_grip),
		track_signals = box_signals(slider_track),
		button_signals = {play_button, file_load_button},
	}
}

// Max is 0, min is pixel_height(slider), this is because the co-ord system of our layout.
calc_slider_grip_val :: proc(current_val: f32, max: f32) -> f32 {
	proposed_value := current_val + (3 * cast(f32)ui_state.mouse.wheel.y)
	if proposed_value < 0 {
		return 0
	} else if proposed_value > max {
		return max
	} else {
		return proposed_value
	}
}

rect_height :: proc(rect: Rect) -> f32 {
	return rect.bottom_right.y - rect.top_left.y
}
rect_width :: proc(rect: Rect) -> f32 {
	return rect.bottom_right.x - rect.top_left.x
}
