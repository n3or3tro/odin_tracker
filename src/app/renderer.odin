// Code associated with turning UI boxes into OpenGL quads.
// Might be able to merge this code with buffers.odin.

package app
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
get_boxes_rendering_data :: proc(box: Box) -> (Rect_Render_Data, Maybe(Rect_Render_Data)) {
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
		border_thickness = 100,
	}
	if s.contains(box.id_string, "step") {
		data.border_thickness = 3
		data.corner_radius = 10
		// if box.selected || box.signals.dragged_over {
		if box.selected {
			data.tl_color = {0.5, 0, 0.7, 1}
			data.bl_color = {0.2, 0, 0.4, 1}
			data.tr_color = {0.8, 0, 0.2, 1}
			data.br_color = {0.9, 0, 0.7, 1}
			data.border_thickness = 100
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
			return data, outlining_rect
		}
	}
	return data, nil
}

is_active_step :: proc(box: Box) -> bool {
	num := step_num_from_step(box.id_string)
	return num == app.audio_state.curr_step
}

get_box_rendering_data :: proc() -> ^[dynamic]Rect_Render_Data {
	// Deffs not efficient to keep realloc'ing and deleting this list, will fix in future.
	rendering_data := new([dynamic]Rect_Render_Data, allocator = context.temp_allocator)
	for box in ui_state.temp_boxes {
		if .Draw in box.flags {
			data, outline_box := get_boxes_rendering_data(box^)
			append(rendering_data, data)
			if outline_box != nil {
				append(rendering_data, outline_box.?)
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
