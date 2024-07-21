// Code to handle text rendering with OpenGL.

package ui_core
import ft "../third_party/freetype"
import alg "core:math/linalg"
import gl "vendor:OpenGL"

// font_path :: "/usr/share/fonts/TTF/Sauce Code Pro Medium Nerd Font Complete.ttf"
font_path :: "/usr/share/fonts/TTF/SauceCodeProNerdFontMono-Medium.ttf"

Character :: struct {
	texture_id: u32,
	size:       [2]f32,
	bearing:    [2]f32,
	advance:    u32,
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
		if ft.load_char(font_face, cast(u64)c, {.Render}) != ft.Error.Ok {
			panic("Failed to load glyph")
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
			texture_id = texture,
			size       = [2]f32 {
				cast(f32)font_face.glyph.bitmap.width,
				cast(f32)font_face.glyph.bitmap.rows,
			},
			bearing    = [2]f32 {
				cast(f32)font_face.glyph.bitmap_left,
				cast(f32)font_face.glyph.bitmap_top,
			},
			advance    = cast(u32)font_face.glyph.advance.x,
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
	vbuffer: ^u32,
	char_map: map[rune]Character,
	window_height: u32,
	x: ^f32,
	y: ^f32,
) {
	set_shader_matrix4(shader, "proj", proj)
	set_shader_vec3(shader, "textColor", color)
	set_shader_u32(shader, "window_height", window_height)
	gl.ActiveTexture(gl.TEXTURE0)
	// iterate through all characters
	for c in text {
		char := char_map[c]
		if char.texture_id == 0 {
			continue
		}

		// update VBO for each character
		w := char.size[0]
		h := char.size[1]
		xpos := x^ + char.bearing[0]
		ypos := 1000 - (y^ - (h - char.bearing[1]))
		
			//odinfmt:disable
		vertices := [6 * 4]f32 {
			xpos, ypos + h, 0, 0,
			xpos, ypos, 0, 1,
			xpos + w, ypos, 1, 1,
			xpos, ypos + h, 0, 0,
			xpos + w, ypos, 1, 1,
			xpos + w, ypos + h, 1, 0
		}
		//odinfmt:enable

		gl.BindTexture(gl.TEXTURE_2D, char.texture_id)
		populate_vbuffer(vbuffer, 0, raw_data(&vertices), size_of(vertices))
		gl.DrawArrays(gl.TRIANGLES, 0, 6)
		x^ += f32((char.advance >> 6))
	}
	gl.BindTexture(gl.TEXTURE_2D, 0)
}

draw_text :: proc(
	text: string,
	vbuffer: ^u32,
	vabuffer: ^u32,
	char_map: map[rune]Character,
	window_dimensions: [2]u32,
) {
	gl.BindVertexArray(vabuffer^)
	enable_layout(0)
	layout_vbuffer(0, 4, gl.FLOAT, gl.FALSE, 4 * size_of(f32), 0)

	text_program := create_and_bind_shader(
		"src/shaders/text_vertex_shader.glsl",
		"src/shaders/text_fragment_shader.glsl",
	)
	text_proj := alg.matrix_ortho3d_f32(
		0,
		cast(f32)window_dimensions.x,
		0,
		cast(f32)window_dimensions.y,
		-1,
		1,
	)
	set_shader_matrix4(text_program, "proj", &text_proj)
	x, y: f32 = 500, 50
	render_text(
		text_program,
		&text_proj,
		text,
		{1, 0, 0},
		vbuffer,
		char_map,
		window_dimensions.y,
		&x,
		&y,
	)
}
