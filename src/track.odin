package main
import "core:fmt"
track_steps :: proc(id_string: string, rect: ^Rect) -> [33]Box_Signals {
	step_size := rect_height(rect^) / 32
	steps: [33]Box_Signals
	for i in 0 ..= 32 {
		step_rect := cut_rect(rect, {Size{.Pixels, step_size}, .Top})
		b := button(
			fmt.aprintf("%s_step_container%d", get_name_from_id_string(id_string), i),
			step_rect,
		)
		steps[i] = b
		append(&ui_state.temp_boxes, b.box)
	}
	return steps
}
