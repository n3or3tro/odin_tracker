// This method only supports rendering characters that are pre-baked. I.e. known
// ahead of time. 
// It should support dynamically resizing this text (need to be cautious of 
// performance concerns though.)
package main
import "core:mem"
import os "core:os/os2"
import "core:strconv"
import str "core:strings"
import "core:unicode/utf8"
import gl "vendor:OpenGL"
import fs "vendor:fontstash"
import tt "vendor:stb/truetype"

Font_Size :: enum {
	xs = 0,
	s  = 1,
	m  = 2,
	l  = 3,
	xl = 4,
}

Atlases :: [5]^Atlas

Atlas :: struct {
	texture: struct {
		width:  i32,
		height: i32,
		pixels: [dynamic]u8,
	},
	chars:   map[rune]Char_Atlas_Metadata,
}

Char_Atlas_Metadata :: struct {
	u0, v0, u1, v1: f32, // normalized uv-cordinates of this char in the atlas - [0,1]
	x0, y0, x1, y1: f32, // i.e. co-ordinates of this letter in the texture.
	// Glyph metrics (for positioning)
	// Store original values of glyph positiong
	glyph_x0:       f32,
	glyph_y0:       f32,
	glyph_x1:       f32,
	glyph_y1:       f32,
	width, height:  f32, // glyph dimensions
	advance_x:      f32,
	bearing_y:      f32, // amount above the baseline, i.e top_left.y
}


create_font_atlas :: proc(
	path: string,
	size: Font_Size,
	allocator: mem.Allocator = context.allocator,
) -> ^Atlas {

	file_data, err := os.read_entire_file_from_path(path, context.allocator)
	assert(err == os.ERROR_NONE, "couldn't read .ttf file")

	font: tt.fontinfo
	res := tt.InitFont(&font, raw_data(file_data), 0)
	if int(res) == 0 {
		panic("failed to init the font fuck me :( ")
	}

	ascent, descent, line_gap: i32
	tt.GetFontVMetrics(&font, &ascent, &descent, &line_gap)
	// Logical Font_Size is hardcode mapped to a point / pixel size. Might be janky.
	font_size: f32
	switch size {
	case .xs:
		font_size = 16
	case .s:
		font_size = 24
	case .m:
		font_size = 32
	case .l:
		font_size = 40
	case .xl:
		font_size = 48
	case:
		panic("font_size was not one of: {.xs, .s, .m, .l, xl}")
	}
	scale := tt.ScaleForPixelHeight(&font, font_size)

	atlas := new(Atlas)
	atlas.chars = make(map[rune]Char_Atlas_Metadata)
	// Calculate the atlas dimensions first, to avoid a bunch of allocations / reallocations.
	// i.e we could do this in one pass, but two passes seems beter. To save *some* amount of time
	// we could cache the results of tt.*() calls, as we make the exact same calls in the loop
	// below.
	atlas_width, max_height: i32
	for i in 32 ..< 127 {
		advance, left_bearing: i32
		ch := rune(i)
		tt.GetCodepointHMetrics(&font, ch, &advance, &left_bearing)
		x0, y0, x1, y1: i32
		tt.GetCodepointBitmapBox(&font, ch, scale, scale, &x0, &y0, &x1, &y1)
		glyph_width := x1 - x0
		glyph_height := y1 - y0
		atlas_width += glyph_width + 1 // + 1 for padding to reduce bleed.
		if glyph_height > max_height {
			max_height = glyph_height
		}
	}
	atlas.texture.width = atlas_width
	atlas.texture.height = max_height + i32(abs(f32(descent) * scale)) + i32(abs(f32(ascent) * scale))
	atlas.texture.pixels = make([dynamic]u8, atlas.texture.width * atlas.texture.height)

	// Pack glyphs into atlas texture
	current_x: i32
	baseline_y := i32(f32(ascent) * scale)
	for i in 32 ..< 127 {
		ch := rune(i)
		glyph_index := i - 32

		// Get glyph metrics
		advance, left_bearing: i32
		tt.GetCodepointHMetrics(&font, ch, &advance, &left_bearing)

		x0, y0, x1, y1: i32
		tt.GetCodepointBitmapBox(&font, ch, scale, scale, &x0, &y0, &x1, &y1)

		glyph_width := x1 - x0
		glyph_height := y1 - y0

		// Render glyph directly into atlas.
		// if glyph_width > 0 && glyph_height > 0 {
		curr_address_to_render_to := mem.ptr_offset(
			raw_data(atlas.texture.pixels),
			(baseline_y + y0) * atlas.texture.width + current_x + x0,
		)
		tt.MakeCodepointBitmap(
			&font,
			curr_address_to_render_to,
			glyph_width,
			glyph_height,
			atlas.texture.width,
			scale,
			scale,
			ch,
		)
		// Store glyph into our hashmap
		new_char_metadata := Char_Atlas_Metadata {
			// Atlas positions (for texture sampling)
			x0        = f32(current_x + x0),
			y0        = f32(baseline_y + y0),
			x1        = f32(current_x + x1),
			y1        = f32(baseline_y + y1),

			// UV coordinates
			u0        = f32(current_x + x0) / f32(atlas.texture.width),
			v0        = f32(baseline_y + y0) / f32(atlas.texture.height),
			u1        = f32(current_x + x1) / f32(atlas.texture.width),
			v1        = f32(baseline_y + y1) / f32(atlas.texture.height),

			// Glyph metrics (for positioning)
			glyph_x0  = f32(x0), // Store original values!
			glyph_y0  = f32(y0),
			glyph_x1  = f32(x1),
			glyph_y1  = f32(y1),
			advance_x = f32(advance) * scale,
			bearing_y = f32(-y0), // Distance from baseline to top
			width     = f32(glyph_width),
			height    = f32(glyph_height),
		}
		atlas.chars[ch] = new_char_metadata
		current_x += glyph_width + 1
	}
	return atlas
}

setup_font_atlas :: proc(size: Font_Size) {
	ui_state.font_atlases[size] = create_font_atlas(font_path, size)
	// printfln("created atlas for size {} - {}\n\n", size, ui_state.font_atlases[size])
	font_texture_data := raw_data(ui_state.font_atlases[size].texture.pixels)
	font_texture_id: u32
	switch size {
	case .xs:
		gl.ActiveTexture(gl.TEXTURE0)
		gl.GenTextures(1, &font_texture_id)
	case .s:
		gl.ActiveTexture(gl.TEXTURE1)
		gl.GenTextures(1, &font_texture_id)
	case .m:
		gl.ActiveTexture(gl.TEXTURE2)
		gl.GenTextures(1, &font_texture_id)
	case .l:
		gl.ActiveTexture(gl.TEXTURE3)
		gl.GenTextures(1, &font_texture_id)
	case .xl:
		gl.ActiveTexture(gl.TEXTURE4)
		gl.GenTextures(1, &font_texture_id)
	}
	gl.BindTexture(gl.TEXTURE_2D, font_texture_id)

	// Set texture parameters (wrap/filter) for font
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

	// Important for single-channel textures!
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)

	x, y, actual_channels_in_image: i32

	// Upload to GPU
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.R8,
		i32(ui_state.font_atlases[size].texture.width),
		i32(ui_state.font_atlases[size].texture.height),
		0,
		gl.RED,
		gl.UNSIGNED_BYTE,
		rawptr(font_texture_data),
	)
	// These can probably go inside the first switch statement, but not sure yet, so put them here
	// as to replicate the original font texture loading for now.
	switch size {
	case .xs:
		set_shader_i32(ui_state.quad_shader_program, "font_texture_xs", 0)
	case .s:
		set_shader_i32(ui_state.quad_shader_program, "font_texture_s", 1)
	case .m:
		set_shader_i32(ui_state.quad_shader_program, "font_texture_m", 2)
	case .l:
		set_shader_i32(ui_state.quad_shader_program, "font_texture_l", 3)
	case .xl:
		set_shader_i32(ui_state.quad_shader_program, "font_texture_xl", 4)
	}
}


// Gives you the first 'point' along the 'baseline' that
// a string will be rendered on.
get_font_baseline :: proc(text: string, box: Box) -> (x, y: f32) {
	rect := box.rect
	max_height: f32 = -1
	str_width: f32 = 0
	font_size := box.font_size
	for ch in text {
		height := f32(ui_state.font_atlases[font_size].chars[ch].height)
		if height > max_height {
			max_height = height
		}
		str_width += f32(ui_state.font_atlases[font_size].chars[ch].advance_x)
	}
	if .Text_Left in box.flags {
		x = rect.top_left.x + f32(app.ui_state.text_box_padding)
	} else if .Text_Right in box.flags {
		// figure this out when we need it :)
	} else { 	// default case is to center text.
		x = rect.top_left.x + (rect_width(rect) - str_width) / 2
	}
	y = rect.bottom_right.y - (rect_height(rect) - max_height) / 2
	return x, y
}

word_rendered_length :: proc(s: string, font_size: Font_Size) -> int {
	tot: f32 = 0
	// Make sure this isn't off by one!!
	for ch in s[0:len(s)] {
		tot += ui_state.font_atlases[font_size].chars[ch].advance_x
	}
	return int(tot)
}


tallest_rendered_char :: proc(s: string, font_size: Font_Size) -> f32 {
	tallest: f32 = 0
	for ch in s {
		if ui_state.font_atlases[font_size].chars[ch].height > tallest {
			tallest = ui_state.font_atlases[font_size].chars[ch].height
		}
	}
	if tallest == 0 {
		panic("tallest still == 0 after trying to get tallest character")
	}
	return tallest
}
