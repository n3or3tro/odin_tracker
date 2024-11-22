package main
import "core:fmt"
track_steps :: proc(id_string: string, rect: ^Rect) -> [33]Box_Signals {
	step_size := rect_height(rect^) / 32
	steps: [33]Box_Signals
	for i in 0 ..= 31 {
		step_rect := cut_rect(rect, {Size{.Pixels, step_size}, .Top})
		beat_rect_width := rect_width(get_rect(step_rect, {Size{.Percent, 0.25}, .Left}))
		track_name := get_name_from_id_string(id_string)

		beat1 := cut_rect(&step_rect, {Size{.Pixels, beat_rect_width}, .Left})
		b1_rect := button(fmt.aprintf("%s_step%d_beat1", track_name, i), beat1)

		beat2 := cut_rect(&step_rect, {Size{.Pixels, beat_rect_width}, .Left})
		b2_rect := button(fmt.aprintf("%s_step%d_beat2", track_name, i), beat2)

		beat3 := cut_rect(&step_rect, {Size{.Pixels, beat_rect_width}, .Left})
		b3_rect := button(fmt.aprintf("%s_step%d_beat3", track_name, i), beat3)

		beat4 := cut_rect(&step_rect, {Size{.Pixels, beat_rect_width}, .Left})
		b4_rect := button(fmt.aprintf("%s_step%d_beat4", track_name, i), beat4)

		append(&ui_state.temp_boxes, b1_rect.box)
		append(&ui_state.temp_boxes, b2_rect.box)
		append(&ui_state.temp_boxes, b3_rect.box)
		append(&ui_state.temp_boxes, b4_rect.box)
	}
	return steps
}
