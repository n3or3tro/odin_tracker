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
import fs "vendor:fontstash"
import tt "vendor:stb/truetype"

Atlases :: struct {
	xs: ^Atlas,
	s:  ^Atlas,
	m:  ^Atlas,
	l:  ^Atlas,
	xl: ^Atlas,
}

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
	font_size: u32,
	allocator: mem.Allocator = context.allocator,
) -> ^Atlas {
	file_data, err := os.read_entire_file_from_path(path, context.allocator)
	if !(err == os.ERROR_NONE) {
		panic("couldnt read .ttf file")
	}
	// font_buffer := make([dynamic]u8, len(file_data))
	font: tt.fontinfo
	res := tt.InitFont(&font, raw_data(file_data), 0)
	if int(res) == 0 {
		println("failed to init the font fuck me :( ")
		// panic()
	}

	ascent, descent, line_gap: i32
	tt.GetFontVMetrics(&font, &ascent, &descent, &line_gap)
	scale := tt.ScaleForPixelHeight(&font, f32(font_size))

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
		// In create_font_atlas, after storing the metadata for 'i':
		// if ch == 'i' || ch == 'l' || ch == 't' || ch == 'T' || ch == 'm' {
		// 	printfln("Character '{}' metrics:", ch)
		// 	printfln("  x0={}, y0={}, x1={}, y1={}", x0, y0, x1, y1)
		// 	printfln("  glyph_width={}, glyph_height={}", glyph_width, glyph_height)
		// 	printfln("  advance={}, scale={}", advance, scale)
		// 	printfln("  advance_x={}", new_char_metadata.advance_x)
		// }
		// // In create_font_atlas
		// if ch == 'i' || ch == 'l' || ch == 't' || ch == 'T' || ch == 'm' {
		// 	printfln("Character '{}' metrics:", ch)
		// 	printfln("  x0={}, x1={}, width={}", x0, x1, glyph_width)
		// 	printfln("  advance={} (scaled={})", advance, f32(advance) * scale)
		// }
		atlas.chars[ch] = new_char_metadata
		current_x += glyph_width + 1
	}
	return atlas
}


// Gives you the first 'point' along the 'baseline' that
// a string will be rendered on.
get_font_baseline :: proc(text: string, box: Box) -> (x, y: f32) {
	rect := box.rect
	max_height: f32 = -1
	str_width: f32 = 0
	for ch in text {
		height := f32(ui_state.font_atlas.chars[ch].height)
		if height > max_height {
			max_height = height
		}
		str_width += f32(ui_state.font_atlas.chars[ch].advance_x)
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

word_rendered_length :: proc(s: string) -> int {
	tot: f32 = 0
	// Make sure this isn't off by one!!
	for ch in s[0:len(s)] {
		tot += ui_state.font_atlas.chars[ch].advance_x
	}
	return int(tot)
}

tallest_rendered_char :: proc(s: string) -> f32 {
	tallest: f32 = 0
	for ch in s {
		if ui_state.font_atlas.chars[ch].height > tallest {
			tallest = ui_state.font_atlas.chars[ch].height
		}
	}
	if tallest == 0 {
		panic("tallest still == 0 after trying to get tallest character")
	}
	return tallest
}
