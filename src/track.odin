package main
import "core:fmt"
track_steps :: proc(id_string: string, rect: ^Rect) {
	step_size := rect_height(rect^) / 32
	for i in 0 ..= 32 {
		step_rect := cut_rect(rect, {Size{.Pixels, step_size}, .Top})
		b := button(
			fmt.aprintf("%s_step_container%d", get_name_from_id_string(id_string), i),
			step_rect,
		)
		append(&ui_state.temp_boxes, b.box)
	}
}
