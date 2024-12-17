package main
import "core:fmt"
import gl "vendor:OpenGL"

create_ui :: proc() {
	track_padding: u32 = 10
	track_width: f32 = f32(wx^ / i32(n_tracks)) - f32(track_padding)
	for i in 0 ..= 9 {
		create_track(u32(i), track_width)
		spacer(
			fmt.aprintf("track_spacer%s@1", i, allocator = context.temp_allocator),
			RectCut{Size{.Pixels, f32(track_padding)}, .Left},
		)
	}
}

render_ui :: proc() {
	if !ui_state.first_frame {
		rect_rendering_data := get_box_rendering_data(ui_state)
		defer delete_dynamic_array(rect_rendering_data^)
		n_rects := u32(len(rect_rendering_data))
		populate_vbuffer_with_rects(
			quad_vabuffer,
			0,
			raw_data(rect_rendering_data^),
			n_rects * size_of(Rect_Render_Data),
		)
		gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, i32(n_rects))
	}
}
