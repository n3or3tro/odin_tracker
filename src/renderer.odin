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
		pos:            [2]i32,
		left_pressed:   bool,
		right_pressed:  bool,
		left_released:  bool,
		right_released: bool,
		wheel:          [2]i8, //-1 moved down, +1 move up
	},
	// layout_stack:  Layout_Stack,
	box_cache:     Box_Cache, // cross-frame cache of boxes
	char_map:      map[rune]Character,
	temp_boxes:    [dynamic]^Box, // store boxes so we can access them when rendering
	first_frame:   bool,
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
	top_left:     Vec2,
	bottom_right: Vec2,
	color:        Vec4,
}

get_box_rendering_data :: proc(ui_state: ^UI_State) -> ^[dynamic]Rect_Render_Data {
	// Deffs not efficient to keep realloc'ing and deleting this list, will fix in future.
	rendering_data := new([dynamic]Rect_Render_Data)
	for box in ui_state.temp_boxes {
		if .Draw in box.flags {
			data := Rect_Render_Data{box.rect.top_left, box.rect.bottom_right, box.color}
			append(rendering_data, data)
		}
	}
	return rendering_data
}

clear :: proc() {
	gl.ClearColor(1, 1, 1, 1.0)
	gl.Clear(gl.COLOR_BUFFER_BIT)
}

draw :: proc(n_vertices: i32, indices: [^]u32) {
	gl.DrawElements(gl.TRIANGLES, n_vertices, gl.UNSIGNED_INT, indices)
}
