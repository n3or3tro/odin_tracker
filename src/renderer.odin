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
	window:          ^sdl.Window,
	renderer_data:   ^Renderer_Data,
	mouse:           struct {
		pos:            [2]i32,
		left_pressed:   bool,
		right_pressed:  bool,
		left_released:  bool,
		right_released: bool,
		wheel:          [2]i8, //-1 moved down, +1 move up
	},
	// layout_stack:  Layout_Stack,
	box_cache:       Box_Cache, // cross-frame cache of boxes
	char_map:        map[rune]Character,
	temp_boxes:      [dynamic]^Box, // store boxes so we can access them when rendering
	first_frame:     bool,
	window_width:    u32,
	window_height:   u32,
	// used to determine the top rect which rect cuts are taken from
	rect_stack:      [dynamic]^Rect,
	rect_hash_cache: map[string][]byte,
}

MyRect :: struct {
	x: f32,
	y: f32,
	w: f32,
	h: f32,
}

Vertex :: struct {
	pos:   Vec2,
	color: Vec4,
}

Renderer_Data :: struct {
	indices:      [dynamic]u32,
	vertices:     [dynamic]Vertex,
	raw_vertices: [dynamic]f32,
	n_quads:      u32,
}

// Assumes a box is 4 vertices (might break if we change to pass more info to GL later)
renderer_add_box :: proc(ui_state: ^UI_State, box: Box) {
	ui_state.renderer_data.n_quads += 1
	vertex_data := raw_vertex_data(vertices_of_box(box))
	for i in 0 ..< 24 {
		append(&ui_state.renderer_data.raw_vertices, vertex_data[i])
	}
	// Definitely not efficient to delete and reallocate the indices every time
	// we add a new quad.
	if ui_state.renderer_data.indices != nil {
		delete(ui_state.renderer_data.indices)
	}
	ui_state.renderer_data.indices = generate_indices(ui_state.renderer_data.n_quads)
}

render_boxes :: proc(ui_state: ^UI_State) {
	// println("temp_boxes:", ui_state.temp_boxes, "\n\n")
	for box in ui_state.temp_boxes {
		if .Draw in box.flags {
			renderer_add_box(ui_state, box^)
		}
	}
}

clear :: proc() {
	// gl.ClearColor(0.5, 0.7, 1.0, 1.0)
	gl.ClearColor(1, 1, 1, 1.0)
	gl.Clear(gl.COLOR_BUFFER_BIT)
}

draw :: proc(n_vertices: i32, indices: [^]u32) {
	// clear()
	gl.DrawElements(gl.TRIANGLES, n_vertices, gl.UNSIGNED_INT, indices)
}
