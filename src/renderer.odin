// Code associated with turning UI boxes into OpenGL quads.
// Might be able to merge this code with buffers.odin.

package main
import "core:fmt"
import alg "core:math/linalg"
import "core:math/rand"
import s "core:strings"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

PI :: 3.14159265359


MyRect :: struct #packed {
	x: f32,
	y: f32,
	w: f32,
	h: f32,
}

Rect_Render_Data :: struct {
	top_left:             Vec2,
	bottom_right:         Vec2,
	texture_top_left:     Vec2,
	texture_bottom_right: Vec2,
	tl_color:             Vec4,
	tr_color:             Vec4,
	bl_color:             Vec4,
	br_color:             Vec4,
	corner_radius:        f32,
	edge_softness:        f32,
	border_thickness:     f32,
}


// sets circumstantial rendering data like radius, borders, etc
get_boxes_rendering_data :: proc(box: Box) -> ^[dynamic]Rect_Render_Data {
	render_data := new([dynamic]Rect_Render_Data, allocator = context.temp_allocator)
	bl_color: Vec4 = box.color
	br_color: Vec4 = box.color
	// tr_color: Vec4 = box.color
	// tl_color: Vec4 = box.color

	if box.signals.pressed && .Active_Animation in box.flags {
		bl_color = {0.0, 0.0, 0.0, 1}
		br_color = {0.0, 0.0, 0.0, 1}
	} else if box.signals.hovering && .Hot_Animation in box.flags {
		bl_color.a = 0.1
		br_color.a = 0.1
	}

	data: Rect_Render_Data = {
		top_left         = box.rect.top_left,
		bottom_right     = box.rect.bottom_right,
		// idrk the winding order for colors, this works tho.
		tl_color         = box.color,
		tr_color         = bl_color,
		bl_color         = box.color,
		br_color         = br_color,
		corner_radius    = 0,
		edge_softness    = 0,
		border_thickness = 300,
	}
	if s.contains(box.id_string, "step") {
		data.border_thickness = 3
		data.corner_radius = 10
		if box.selected {
			data.tl_color = {0.5, 0, 0.7, 1}
			data.bl_color = {0.2, 0, 0.4, 1}
			data.tr_color = {0.8, 0, 0.2, 1}
			data.br_color = {0.9, 0, 0.7, 1}
			data.border_thickness = 100

			// create text box to show step's pitch.
			track_num := track_num_from_step(box.id_string)
			step_num := step_num_from_step(box.id_string)
			pitch := ui_state.step_pitches[track_num][step_num]
			// Might get iffy creating this here instead of inside the builder code
			// of the UI
			pitch_box :=
				text_box(tprintf("{}@track{}{}-pitch", pitch, track_num, step_num), box.rect).box_signals.box

			pitch_render_data := Rect_Render_Data {
				top_left         = pitch_box.rect.top_left,
				bottom_right     = pitch_box.rect.bottom_right,
				tl_color         = pitch_box.color,
				bl_color         = pitch_box.color,
				br_color         = pitch_box.color,
				tr_color         = pitch_box.color,
				corner_radius    = 0,
				edge_softness    = 0,
				border_thickness = 100,
			}
			append(render_data, data, pitch_render_data)
		}
		if is_active_step(box) {
			data.border_thickness = 100
			data.corner_radius = 0
			outlining_rect := data
			outlining_rect.border_thickness = 5
			outlining_rect.tl_color = {1, 0, 0, 1}
			outlining_rect.tr_color = {1, 0, 0, 1}
			outlining_rect.bl_color = {1, 0, 0, 1}
			outlining_rect.br_color = {1, 0, 0, 1}


			append(render_data, data, outlining_rect)
			return render_data
			// return data, outlining_rect
		}
	}
	append(render_data, data)
	return render_data
}

is_active_step :: proc(box: Box) -> bool {
	num := step_num_from_step(box.id_string)
	return num == app.audio_state.curr_step
}

get_all_rendering_data :: proc() -> ^[dynamic]Rect_Render_Data {
	// Deffs not efficient to keep realloc'ing and deleting this list, will fix in future.
	rendering_data := new([dynamic]Rect_Render_Data, allocator = context.temp_allocator)
	for box in ui_state.temp_boxes {
		if .Draw in box.flags {
			boxes_to_render := get_boxes_rendering_data(box^)
			defer delete(boxes_to_render^)
			for data in boxes_to_render {
				append(rendering_data, data)
			}
		}
	}
	return rendering_data
}

// Need to name this and the other text renderings functions better.
render_text2 :: proc() {
	for box in ui_state.temp_boxes {
		if .Draw_Text in box.flags {
			xx, yy := get_font_baseline(box.name, box.rect)
			x, y := f32(xx), f32(yy)
			draw_text(box.name, x, y)
		}
	}
}

// At the moment, assume pcm_frames is from a mono version of the .wav file.
render_waveform :: proc(rect: Rect, pcm_frames: [dynamic]f32) {
	render_width := rect_width(rect)
	render_height := rect_height(rect)
	frames_read := u64(len(pcm_frames))
	waveform_vertices := make_dynamic_array([dynamic][2]f32)
	for x in 0 ..< render_width {
		start := u64((f64(x) / f64(render_width)) * f64(frames_read))
		end := u64(f64(x + 1) / f64(render_width) * f64(frames_read))
		if end >= frames_read {end = frames_read}
		min: f32 = 1
		max: f32 = -1
		for i in start ..< end {
			if pcm_frames[i] < min {min = pcm_frames[i]}
			if pcm_frames[i] > max {max = pcm_frames[i]}
		}
		// y1 := screen_height / 2 - int(max * f32(screen_height / 2))
		// y2 := screen_height / 2 - int(min * f32(screen_height / 2))
		norm_x: f32 = f32(x) / render_width
		x_pos := rect.top_left.x + norm_x * render_width
		y_top := rect.top_left.y + (0.5 - max * 0.5) * render_height
		y_bot := rect.top_left.y + (0.5 - min * 0.5) * render_height

		append(&waveform_vertices, [2]f32{x_pos, y_top})
		append(&waveform_vertices, [2]f32{x_pos, y_bot})

		vao: u32
		vbo: u32
		gl.GenVertexArrays(1, &vao)
		gl.BindVertexArray(vao)

		gl.GenBuffers(1, &vbo)
		gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
		gl.BufferData(
			gl.ARRAY_BUFFER,
			len(waveform_vertices),
			raw_data(waveform_vertices),
			gl.DYNAMIC_DRAW,
		)

		gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(f32) * 2, 0)
		gl.EnableVertexArrayAttrib(vao, 0)
	}
}

setup_for_quads :: proc(shader_program: ^u32) {
	//odinfmt:disable
	gl.BindVertexArray(ui_state.quad_vabuffer^)
	bind_shader(shader_program^)

	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, size_of(Rect_Render_Data), 0)
	gl.VertexAttribDivisor(0, 1)
	enable_layout(0)

	gl.VertexAttribPointer(1, 2, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, bottom_right))
	enable_layout(1)
	gl.VertexAttribDivisor(1, 1)

	// Trying to pass in a [4]vec4 for colors was fucky, so did this. Should clean up later.
	gl.VertexAttribPointer(2, 4, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, tl_color))
	enable_layout(2)
	gl.VertexAttribDivisor(2, 1)

	gl.VertexAttribPointer(3, 4, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, tr_color))
	enable_layout(3)
	gl.VertexAttribDivisor(3, 1)

	gl.VertexAttribPointer(4, 4, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, bl_color))
	enable_layout(4)
	gl.VertexAttribDivisor(4, 1)

	gl.VertexAttribPointer(5, 4, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, br_color))
	enable_layout(5)
	gl.VertexAttribDivisor(5, 1)

	gl.VertexAttribPointer(6, 1, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, corner_radius))
	enable_layout(6)
	gl.VertexAttribDivisor(6, 1)


	gl.VertexAttribPointer(7, 1, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, edge_softness))
	enable_layout(7)
	gl.VertexAttribDivisor(7, 1)

	gl.VertexAttribPointer(8, 1, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, border_thickness))
	enable_layout(8)
	gl.VertexAttribDivisor(8, 1)
	//odinfmt:enable
}

reset_renderer_data :: proc() {
	clear_dynamic_array(&ui_state.temp_boxes)
	ui_state.first_frame = false
}

clear_screen :: proc() {
	gl.ClearColor(0, 0.5, 1, 0.5)
	gl.Clear(gl.COLOR_BUFFER_BIT)
}


draw :: proc(n_vertices: i32, indices: [^]u32) {
	gl.DrawElements(gl.TRIANGLES, n_vertices, gl.UNSIGNED_INT, indices)
}
