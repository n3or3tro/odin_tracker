// Code associated with turning UI boxes into OpenGL quads.
// Might be able to merge this code with buffers.odin.

package main
import "core:fmt"
import "core:math"
import alg "core:math/linalg"
import "core:math/rand"
import s "core:strings"
import gl "vendor:OpenGL"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"

PI :: math.PI

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
	ui_element_type:      u32,
}

// Kind of the default data when turning an abstract box into an opengl rect.
get_default_rendering_data :: proc(box: Box) -> Rect_Render_Data {
	data: Rect_Render_Data = {
		top_left         = box.rect.top_left,
		bottom_right     = box.rect.bottom_right,
		// idrk the winding order for colors, this works tho.
		tl_color         = box.color,
		tr_color         = box.color,
		bl_color         = box.color,
		br_color         = box.color,
		corner_radius    = 0,
		edge_softness    = 0,
		border_thickness = 300,
	}
	return data
}

// sets circumstantial (hovering, clicked, etc) rendering data like radius, borders, etc
get_boxes_rendering_data :: proc(box: Box) -> ^[dynamic]Rect_Render_Data {
	render_data := new([dynamic]Rect_Render_Data, allocator = context.temp_allocator)
	tl_color: Vec4 = box.color
	bl_color: Vec4 = box.color
	tr_color: Vec4 = box.color
	br_color: Vec4 = box.color

	// shade buttons
	if s.contains(box.id_string, "button") {
		bl_color = {0.2, 0.2, 0.2, 1}
		br_color = {0.2, 0.2, 0.2, 1}
	}

	if box.signals.hovering && .Active_Animation in box.flags {
		bl_color += {0.3, 0.3, 0.3, 0}
		br_color += {0.3, 0.3, 0.3, 0}
	} else if box.signals.hovering && .Hot_Animation in box.flags {
		bl_color.a = 0.1
		br_color.a = 0.1
	}

	// data := get_standard_rendering_data(box)
	data: Rect_Render_Data = {
		top_left         = box.rect.top_left,
		bottom_right     = box.rect.bottom_right,
		// idrk the winding order for colors, this works tho.
		tl_color         = bl_color,
		tr_color         = br_color,
		bl_color         = box.color,
		br_color         = box.color,
		corner_radius    = 0,
		edge_softness    = 0,
		border_thickness = 300,
	}
	if s.contains(box.id_string, "step") {
		data.border_thickness = 100
		data.corner_radius = 0
		if box.selected {
			data.tl_color = {0.5, 0, 0.7, 1}
			data.bl_color = {0.2, 0, 0.4, 1}
			data.tr_color = {0.8, 0, 0.2, 1}
			data.br_color = {0.9, 0, 0.7, 1}
			data.border_thickness = 100
		}
		if is_active_step(box) {
			data.corner_radius = 0
			outlining_rect := data
			outlining_rect.border_thickness = 0.7
			normal_color: Color = {1, 0, 0, 1}
			outline_color: Color = {0.5, 0.5, 0.5, 1}
			outlining_rect.tl_color = normal_color
			outlining_rect.tr_color = normal_color
			outlining_rect.bl_color = normal_color
			outlining_rect.br_color = normal_color
			append(render_data, data, outlining_rect)
			return render_data
		}
	}

	if s.contains(box.id_string, "button") {
		data.corner_radius = 10
	}

	append(render_data, data)

	// These come after adding the main rect data since they have a higher 'z-order'.
	if s.contains(box.id_string, "input") && should_render_text_cursor() {
		color := Color{0, 0.5, 1, 1}
		// cursor_pos_x := box.rect.top_left.x + app.ui_state.text_box_padding + word_rendered_length()
		cursor_data := Rect_Render_Data {
			top_left         = {app.ui_state.text_cursor_x_coord, box.rect.top_left.y + 3},
			bottom_right     = {app.ui_state.text_cursor_x_coord + 5, box.rect.bottom_right.y - 3},
			bl_color         = color,
			tl_color         = color,
			br_color         = color,
			tr_color         = color,
			border_thickness = 300,
			corner_radius    = 0,
			edge_softness    = 2,
		}
		append(render_data, cursor_data)
	}

	if .Draw_Border in box.flags {
		border_rect := data
		border_rect.border_thickness = 0.6
		border_rect.bl_color = {0, 0, 0, 1}
		border_rect.tl_color = {0, 0, 0, 1}
		border_rect.tr_color = {0, 0, 0, 1}
		border_rect.br_color = {0, 0, 0, 1}
		append(render_data, border_rect)
	}
	return render_data
}

// A jank way to 'animate' the text cursor blinking based on frame number.
should_render_text_cursor :: proc() -> bool {
	frame_rate: u64 = 120 // Shouldn't be hardcoded in prod.
	curr_frame := app.ui_state.frame_num^ % frame_rate
	return curr_frame < frame_rate
}

is_active_step :: proc(box: Box) -> bool {
	track_num := track_num_from_step(box.id_string)
	step_num := step_num_from_step(box.id_string)
	return step_num == app.audio_state.tracks[track_num].curr_step
}

get_background_rendering_data :: proc() -> Rect_Render_Data {
	background_box := Box {
		rect = Rect{top_left = {0.0, 0.0}, bottom_right = {f32(app.wx^), f32(app.wy^)}},
		id_string = "background@background",
		visible = true,
	}
	rendering_data := Rect_Render_Data {
		ui_element_type      = 15.0,
		texture_top_left     = {0, 0},
		texture_bottom_right = {1, 1},
		top_left             = {0, 0},
		bottom_right         = {f32(app.wx^), f32(app.wy^)},
	}
	return rendering_data
}

get_all_rendering_data :: proc() -> ^[dynamic]Rect_Render_Data {
	// Deffs not efficient to keep realloc'ing and deleting this list, will fix in future.
	rendering_data := new([dynamic]Rect_Render_Data, allocator = context.temp_allocator)
	append(rendering_data, get_background_rendering_data())
	for box in ui_state.temp_boxes {
		boxes_to_render := get_boxes_rendering_data(box^)
		defer delete(boxes_to_render^)
		if s.contains(get_id_from_id_string(box.id_string), "knob-body") {
			add_knob_rendering_data(box^, rendering_data)
		} else if s.contains(box.id_string, "_grip") {
			add_fader_knob_rendering_data(box^, rendering_data)
		} else if .Draw in box.flags {
			for data in boxes_to_render {
				append(rendering_data, data)
			}
		}
		if .Draw_Text in box.flags {
			add_word_rendering_data(box^, boxes_to_render, rendering_data)
		}
		if s.contains(get_id_from_id_string(box.id_string), "waveform-container") {
			add_waveform_rendering_data(
				box.rect,
				app.audio_state.tracks[0].sound^,
				get_track_pcm_data(0),
				rendering_data,
			)
		}

	}
	return rendering_data
}

add_knob_rendering_data :: proc(box: Box, rendering_data: ^[dynamic]Rect_Render_Data) {
	data := get_default_rendering_data(box)
	data.corner_radius = 0
	data.ui_element_type = 3.0
	data.texture_top_left = {0.0, 0.0}
	data.texture_bottom_right = {1.0, 1.0}
	append(rendering_data, data)
}

add_fader_knob_rendering_data :: proc(box: Box, rendering_data: ^[dynamic]Rect_Render_Data) {
	data := get_default_rendering_data(box)
	data.corner_radius = 0
	data.ui_element_type = 4.0
	data.texture_top_left = {0.0, 0.0}
	data.texture_bottom_right = {1.0, 1.0}
	append(rendering_data, data)
}

add_word_rendering_data :: proc(
	box: Box,
	boxes_to_render: ^[dynamic]Rect_Render_Data,
	rendering_data: ^[dynamic]Rect_Render_Data,
) {
	word_length := word_rendered_length(box.name)
	gap := (int(rect_width(box.rect)) - word_length) / 2
	starting_x, starting_y := get_font_baseline(box.name, box)
	parent_rect := boxes_to_render[len(boxes_to_render) - 1]
	len_so_far: f32 = 0
	for i in 0 ..< len(box.name) {
		ch := rune(box.name[i])
		char_metadata := ui_state.atlas_metadata.chars[ch]
		new_rect := Rect_Render_Data {
			bl_color             = {1, 1, 1, 1},
			br_color             = {1, 1, 1, 1},
			tl_color             = {1, 1, 1, 1},
			tr_color             = {1, 1, 1, 1},
			border_thickness     = 300,
			corner_radius        = 0,
			edge_softness        = 0,
			ui_element_type      = 1.0,
			top_left             = {starting_x + len_so_far, starting_y - 40},
			bottom_right         = {
				starting_x + len_so_far + f32(char_metadata.width),
				starting_y,
			},
			texture_top_left     = {f32(char_metadata.x), f32(char_metadata.y)},
			texture_bottom_right = {
				f32(char_metadata.x + char_metadata.width),
				f32(char_metadata.y + char_metadata.height),
			},
		}
		len_so_far += f32(char_metadata.advance)
		append(rendering_data, new_rect)
	}
}

// Assumes pcm_frames is from a mono version of the .wav file, BOLD assumption.
// Might need to cache calls to this function since it's pretty costly.
add_waveform_rendering_data :: proc(
	rect: Rect,
	sound: ma.sound,
	pcm_frames: [dynamic]f32,
	rendering_data: ^[dynamic]Rect_Render_Data,
) {
	render_width := rect_width(rect)
	render_height := rect_height(rect)
	frames_read := u64(len(pcm_frames))
	wav_rendering_data := make(
		[dynamic]Rect_Render_Data,
		u32(render_width),
		allocator = context.temp_allocator,
	)
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
		norm_x: f32 = f32(x) / render_width
		x_pos := rect.top_left.x + norm_x * render_width
		y_top := rect.top_left.y + (0.5 - max * 0.5) * render_height
		y_bot := rect.top_left.y + (0.5 - min * 0.5) * render_height
		new_data := Rect_Render_Data {
			tl_color         = {1, 0.5, 1, 1},
			bl_color         = {1, 0.5, 0.5, 1},
			tr_color         = {1, 0.5, 1, 1},
			br_color         = {0.7, 0.5, 1, 1},
			border_thickness = 300,
			corner_radius    = 0,
			edge_softness    = 0,
			top_left         = Vec2{x_pos - 0.5, y_top},
			bottom_right     = Vec2{x_pos + 0.5, y_bot},
			ui_element_type  = 2.0,
		}
		append(rendering_data, new_data)
	}
}

setup_for_quads :: proc(shader_program: ^u32) {
	//odinfmt:disable
	gl.BindVertexArray(ui_state.quad_vabuffer^)
	bind_shader(shader_program^)

	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, top_left))
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

	gl.VertexAttribPointer(9, 2, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, texture_top_left))
	enable_layout(9)
	gl.VertexAttribDivisor(9, 1)

	gl.VertexAttribPointer(10, 2, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, texture_bottom_right))
	enable_layout(10)
	gl.VertexAttribDivisor(10, 1)

	gl.VertexAttribPointer(11, 1, gl.INT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, ui_element_type))
	enable_layout(11)
	gl.VertexAttribDivisor(11, 1)

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
