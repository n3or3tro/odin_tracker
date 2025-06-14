// Code to handle text rendering with OpenGL.
// Mostly copied from online sources... forgot to get the URL might need to 
// grab it to re-understand :) 


// Types in this file a little fucky, this is mostly the result of the weird types in vendore:freetype

package main
// import alg "core:math/linalg"
// import ft "third_party/freetype"
// import gl "vendor:OpenGL"
// import stash "vendor:fontstash"

// import "core:fmt"
// import "core:io"
// import os "core:os/os2"
// import "core:strconv"
// import "core:strings"


// Char_Atlas_Metadata :: struct {
// 	x, y, width, height, xoffset, yoffset, advance: int,
// }

// Atlas_Metadata :: struct {
// 	texture: struct {
// 		texture_width, texture_height: int,
// 	},
// 	chars:   map[rune]Char_Atlas_Metadata,
// }

// parse_font_metadata :: proc(path: string) -> Atlas_Metadata {
// 	// parse_fnt_metadata :: proc(path: string) {
// 	fp, err := os.open(path)
// 	if err != os.ERROR_NONE {
// 		panic(tprintf("Could not open .fnt file: %s", path))
// 	}
// 	file_info, _ := os.stat(path, allocator = context.temp_allocator)
// 	file_len := file_info.size
// 	file_bytes := make([]byte, file_len)
// 	bytes_read, _ := os.read(fp, file_bytes)
// 	if bytes_read != int(file_len) {
// 		panic(
// 			tprintf(
// 				"only read %d bytes from %s when we were suppoed to read %d bytes",
// 				bytes_read,
// 				path,
// 				file_len,
// 			),
// 		)
// 	}
// 	file_data := strings.clone_from_bytes(file_bytes)
// 	lines := strings.split(file_data, "\n", allocator = context.temp_allocator)
// 	found_start := false
// 	atlas_char_metadata := make(map[rune]Char_Atlas_Metadata)

// 	// This is too hardcoded.... but assuming the second line is what we want here
// 	println(lines[1])
// 	tex_width_start := strings.index(lines[1], "scaleW=") + 7
// 	tex_height_start := strings.index(lines[1], "scaleH=") + 7
// 	texture_height := strconv.atoi(
// 		lines[1][tex_height_start:strings.index(lines[1][tex_height_start:], " ") + tex_height_start],
// 	)
// 	texture_width := strconv.atoi(
// 		lines[1][tex_width_start:strings.index(lines[1][tex_width_start:], " ") + tex_width_start],
// 	)

// 	for line in lines {
// 		words := strings.split(line, " ", allocator = context.temp_allocator)
// 		if words[0] == "char" {
// 			found_start = true
// 		}
// 		if found_start {
// 			if len(line) == 0 {
// 				continue
// 			}
// 			// println(line)
// 			ascii_code_start := strings.index(line, "id=") + 3
// 			x_start := strings.index(line, "x=") + 2
// 			y_start := strings.index(line, "y=") + 2
// 			width_start := strings.index(line, "width=") + 6
// 			height_start := strings.index(line, "height=") + 7
// 			xoffset_start := strings.index(line, "xoffset=") + 8
// 			yoffset_start := strings.index(line, "yoffset=") + 8
// 			xadvance_start := strings.index(line, "xadvance=") + 9

// 			letter_code := strconv.atoi(
// 				line[ascii_code_start:strings.index(line[ascii_code_start:], " ") + ascii_code_start],
// 			)
// 			letter := rune(letter_code)
// 			x := strconv.atoi(line[x_start:strings.index(line[x_start:], " ") + x_start])
// 			y := strconv.atoi(line[y_start:strings.index(line[y_start:], " ") + y_start])
// 			width := strconv.atoi(line[width_start:strings.index(line[width_start:], " ") + width_start])
// 			height := strconv.atoi(line[height_start:strings.index(line[height_start:], " ") + height_start])
// 			xoffset := strconv.atoi(
// 				line[xoffset_start:strings.index(line[xoffset_start:], " ") + xoffset_start],
// 			)
// 			yoffset := strconv.atoi(
// 				line[yoffset_start:strings.index(line[yoffset_start:], " ") + yoffset_start],
// 			)
// 			xadvance := strconv.atoi(
// 				line[xadvance_start:strings.index(line[xadvance_start:], " ") + xadvance_start],
// 			)
// 			atlas_char_metadata[letter] = Char_Atlas_Metadata {
// 				x,
// 				y,
// 				width,
// 				height,
// 				xoffset,
// 				yoffset,
// 				xadvance,
// 			}
// 		}
// 	}
// 	return Atlas_Metadata{texture = {texture_width, texture_height}, chars = atlas_char_metadata}
// }

// get_chars_box :: proc() {
// }

// get_font_baseline :: proc(text: string, box: Box) -> (x, y: f32) {
// 	rect := box.rect
// 	max_height: f32 = -1
// 	str_width: f32 = 0
// 	for ch in text {
// 		height := f32(ui_state.atlas_metadata.chars[ch].height)
// 		if height > max_height {
// 			max_height = height
// 		}
// 		str_width += f32(ui_state.atlas_metadata.chars[ch].advance)
// 	}
// 	if .Text_Left in box.flags {
// 		x = rect.top_left.x + f32(app.ui_state.text_box_padding)
// 	} else if .Text_Right in box.flags {
// 		// figure this out when we need it :)
// 	} else { 	// default case is to center text.
// 		x = rect.top_left.x + (rect_width(rect) - str_width) / 2
// 	}
// 	// x = rect.top_left.x + (rect_width(rect) - str_width) / 2
// 	y = rect.bottom_right.y - (rect_height(rect) - max_height) / 2
// 	// y = rect.bottom_right.y
// 	return x, y
// }

// tallest_char_height :: proc(s: string) -> int {
// 	hi := -1
// 	for ch in s {
// 		if ui_state.atlas_metadata.chars[ch].height > hi {
// 			hi = ui_state.atlas_metadata.chars[ch].height
// 		}
// 	}
// 	return hi
// }

// word_rendered_length :: proc(s: string) -> int {
// 	tot := 0
// 	// Make sure this isn't off by one!!
// 	for ch in s[0:len(s)] {
// 		tot += ui_state.atlas_metadata.chars[ch].advance
// 	}
// 	return tot
// }
