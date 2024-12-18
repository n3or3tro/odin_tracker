// Code associated with turning UI boxes into OpenGL quads.
// Might be able to merge this code with buffers.odin.

package main
import "core:fmt"
import alg "core:math/linalg"
import "core:math/rand"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

PI :: 3.14159265359

UI_State :: struct {
	window:        ^sdl.Window,
	mouse:         struct {
		pos:           [2]i32,
		left_pressed:  bool,
		right_pressed: bool,
		wheel:         [2]i8, //-1 moved down, +1 move up
	},
	// layout_stack:  Layout_Stack,
	box_cache:     Box_Cache, // cross-frame cache of boxes
	char_map:      map[rune]Character,
	temp_boxes:    [dynamic]^Box, // store boxes so we can access them when rendering
	first_frame:   bool, // dont want to render on the first frame
	window_width:  u32,
	window_height: u32,
	// used to determine the top rect which rect cuts are taken from
	rect_stack:    [dynamic]^Rect,
}

MyRect :: struct #packed {
	x: f32,
	y: f32,
	w: f32,
	h: f32,
}

Rect_Render_Data :: struct {
	top_left:         Vec2,
	bottom_right:     Vec2,
	tl_color:         Vec4,
	tr_color:         Vec4,
	bl_color:         Vec4,
	br_color:         Vec4,
	corner_radius:    f32,
	edge_softness:    f32,
	border_thickness: f32,
}

get_box_rendering_data :: proc(ui_state: ^UI_State) -> ^[dynamic]Rect_Render_Data {
	// Deffs not efficient to keep realloc'ing and deleting this list, will fix in future.
	rendering_data := new([dynamic]Rect_Render_Data, allocator = context.temp_allocator)
	for box in ui_state.temp_boxes {
		if .Draw in box.flags {
			bl_color: Vec4 = box.color
			br_color: Vec4 = box.color
			if box.signals.pressed {
				bl_color = {0.0, 0.0, 0.0, 1}
				br_color = {0.0, 0.0, 0.0, 1}
			} else if box.signals.hovering {
				bl_color.a = 0.1
				br_color.a = 0.1
			} // border_thicknes: f32 = 20 if box.hot else 0
			data: Rect_Render_Data = {
				top_left         = box.rect.top_left,
				bottom_right     = box.rect.bottom_right,
				// idrk the winding order for colors, this works tho.
				tl_color         = box.color,
				tr_color         = bl_color,
				bl_color         = box.color,
				br_color         = br_color,
				corner_radius    = 10,
				edge_softness    = 0,
				border_thickness = 20,
			}
			append(rendering_data, data)
		}
	}
	return rendering_data
}

setup_for_quads :: proc(shader_program: ^u32) {
	//odinfmt:disable
	gl.BindVertexArray(quad_vabuffer^)
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
	gl.ClearColor(1, 1, 1, 1.0)
	gl.Clear(gl.COLOR_BUFFER_BIT)
}


draw :: proc(n_vertices: i32, indices: [^]u32) {
	gl.DrawElements(gl.TRIANGLES, n_vertices, gl.UNSIGNED_INT, indices)
}
