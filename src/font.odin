// Code to handle text rendering with OpenGL.
// Mostly copied from online sources... forgot to get the URL might need to 
// grab it to re-understand :) 


// Types in this file a little fucky, this is mostly the result of the weird types in vendore:freetype

package main
import alg "core:math/linalg"
import ft "third_party/freetype"
// import "vendor:"
import gl "vendor:OpenGL"

// font_path :: "/usr/share/fonts/TTF/Sauce Code Pro Medium Nerd Font Complete.ttf"
when ODIN_OS == .Windows {
	font_path :: "C:\\windows\\fonts\\arial.ttf"
} else {
	font_path :: "/usr/share/fonts/TTF/SauceCodeProNerdFontMono-Medium.ttf"
}

Character :: struct {
	texture_id:   u32,
	size:         [2]f32,
	bearing:      [2]f32,
	advance:      u32,
	glyph_width:  f32,
	glyph_height: f32,
}

create_font_map :: proc(font_size: u32) -> map[rune]Character {
	char_map := make(map[rune]Character)
	font_lib: ft.Library
	if ft.init_free_type(&font_lib) != ft.Error.Ok {
		panic("Failed to initialize FreeType library")
	}
	font_face: ft.Face
	if ft.new_face(font_lib, font_path, 0, &font_face) != ft.Error.Ok {
		panic("Failed to load font")
	}

	ft.set_pixel_sizes(font_face, 0, font_size)

	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	for c := rune(0); c < 128; c += 1 {
		// This annoying check is coz the u64/u32 cast, which differs on diff OSs.
		when ODIN_OS == .Windows {
			if ft.load_char(font_face, cast(u32)c, {.Render}) != ft.Error.Ok {
				panic("Failed to load glyph")
			}
		} else {
			if ft.load_char(font_face, cast(u64)c, {.Render}) != ft.Error.Ok {
				panic("Failed to load glyph")
			}
		}
		// Generate texture
		texture: u32
		gl.GenTextures(1, &texture)
		gl.BindTexture(gl.TEXTURE_2D, texture)
		gl.TexImage2D(
			gl.TEXTURE_2D,
			0,
			gl.RED,
			cast(i32)font_face.glyph.bitmap.width,
			cast(i32)font_face.glyph.bitmap.rows,
			0,
			gl.RED,
			gl.UNSIGNED_BYTE,
			font_face.glyph.bitmap.buffer,
		)
		// 	// Set texture options
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
		// 	// Now store character for later use
		new_char := Character {
			texture_id   = texture,
			size         = [2]f32 {
				cast(f32)font_face.glyph.bitmap.width,
				cast(f32)font_face.glyph.bitmap.rows,
			},
			bearing      = [2]f32 {
				cast(f32)font_face.glyph.bitmap_left,
				cast(f32)font_face.glyph.bitmap_top,
			},
			advance      = cast(u32)font_face.glyph.advance.x,
			glyph_width  = cast(f32)font_face.glyph.metrics.width / 64,
			glyph_height = cast(f32)font_face.glyph.metrics.height / 64,
		}
		char_map[c] = new_char
	}
	ft.done_face(font_face)
	ft.done_free_type(font_lib)
	return char_map
}

render_text :: proc(
	shader: u32,
	proj: ^alg.Matrix4x4f32,
	text: string,
	color: [3]f32,
	x: f32,
	y: f32,
) {
	window_height := cast(u32)wy^
	set_shader_matrix4(shader, "proj", proj)
	set_shader_vec3(shader, "textColor", color)
	set_shader_u32(shader, "window_height", window_height)
	gl.ActiveTexture(gl.TEXTURE0)
	// create this because of weird non-mutable proc arg stuff
	x := x
	for ch in text {
		char := ui_state.char_map[ch]
		if char.texture_id == 0 {
			continue
		}

		// update VBO for each character
		w := char.size[0]
		h := char.size[1]
		xpos := x + char.bearing[0]
		// vvv chatgpt fixed vvv
		ypos := (f32(window_height) - y) + char.bearing[1] - h
		
			//odinfmt:disable
		vertices := [6 * 4]f32 {
			xpos, 		ypos + h, 	0, 0,
			xpos, 		ypos, 		0, 1,
			xpos + w, 	ypos, 		1, 1,
			xpos, 		ypos + h, 	0, 0,
			xpos + w, 	ypos, 		1, 1,
			xpos + w, 	ypos + h, 	1, 0,
		}
		//odinfmt:enable


		gl.BindTexture(gl.TEXTURE_2D, char.texture_id)
		populate_vbuffer(text_vbuffer, 0, raw_data(&vertices), size_of(vertices))
		gl.DrawArrays(gl.TRIANGLES, 0, 6)
		x += f32((char.advance >> 6))
	}
	gl.BindTexture(gl.TEXTURE_2D, 0)
}

draw_text :: proc(text: string, x, y: f32) {
	if !ui_state.first_frame {

		gl.BindVertexArray(text_vabuffer^)
		enable_layout(0)
		layout_vbuffer(0, 4, gl.FLOAT, gl.FALSE, 4 * size_of(f32), 0)

		bind_shader(text_shader_program)
		text_proj := alg.matrix_ortho3d_f32(0, cast(f32)wx^, 0, cast(f32)wy^, -1, 1)
		set_shader_matrix4(text_shader_program, "proj", &text_proj)
		render_text(text_shader_program, &text_proj, text, {1, 0, 0}, x, y)

		setup_for_quads(&quad_shader_program)
	}
}

get_font_baseline :: proc(text: string, rect: Rect) -> (x, y: f32) {
	max_height: f32 = -1
	str_width: f32 = 0
	for ch in text {
		height := ui_state.char_map[ch].glyph_height
		if height > max_height {
			max_height = height
		}
		str_width += ui_state.char_map[ch].glyph_width
	}
	y = rect.bottom_right.y - (rect_height(rect) - max_height) / 2
	x = rect.top_left.x + (rect_width(rect) - str_width) / 2
	return x, y
}
