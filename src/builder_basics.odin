// Builder basics, buttons, containers, etc.
package main
import "core:bytes"
import "core:hash"
import "core:math"
import "core:math/rand"
import "core:strconv"
import str "core:strings"
import "core:text/edit"
import "core:unicode"
import sdl "vendor:sdl2"

Draggable_Container_Signals :: struct {
	handle_bar: Box_Signals,
	container:  Box_Signals,
}

Text_Input_Signals :: struct {
	box_signals: Box_Signals,
	new_string:  string,
	cursor_pos:  int,
}

container :: proc(id_string: string, rect: Rect, metadata: Box_Metadata = {}) -> Box_Signals {
	b := box_from_cache({}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

clickable_container :: proc(id_string: string, rect: Rect, metadata: Box_Metadata = {}) -> Box_Signals {
	b := box_from_cache({.Clickable}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

line :: proc(id_string: string, rect: Rect, metadata: Box_Metadata = {}) -> Box_Signals {
	b := box_from_cache({.Draw}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

draggable_container :: proc(
	id_string: string,
	rect: ^Rect,
	metadata: Box_Metadata = {},
) -> Draggable_Container_Signals {
	handle_bar_rect := cut_rect(rect, RectCut{side = .Top, size = {.Percent, 0.05}})
	handle_bar := text_button(tprintf("drag-me@{}-handle-bar", id_string), handle_bar_rect)
	b := box_from_cache({.Floating_X, .Draw}, id_string, rect^)
	append(&ui_state.temp_boxes, b)
	return Draggable_Container_Signals{handle_bar = handle_bar, container = box_signals(b)}
}

text_container :: proc(id_string: string, rect: Rect, metadata: Box_Metadata = {}) -> Box_Signals {
	b := box_from_cache({.Draw_Text}, id_string, rect)
	b.color = {1, 1, 1, 1}
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

// Lets you draw a text container at an absolute x,y position and calculates size
// based on the font. ui_state.font_size has to be set if you want the right font size.
text_container_absolute :: proc(id_string: string, x, y: f32, metadata: Box_Metadata = {}) -> Box_Signals {
	name := get_name_from_id_string(id_string)
	length := f32(word_rendered_length(name, ui_state.font_size))
	height := tallest_rendered_char(name, ui_state.font_size)
	rect := Rect{{x, y}, {x + length, y + height}}
	b := box_from_cache({.Draw_Text}, id_string, rect)
	b.color = {1, 1, 1, 1}
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

button :: proc(id_string: string, rect: Rect, metadata: Box_Metadata = {}) -> Box_Signals {
	b := box_from_cache({.Draw, .Clickable, .Active_Animation, .Hot_Animation}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

text_button :: proc(id_string: string, rect: Rect, metadata: Box_Metadata = {}) -> Box_Signals {
	b := box_from_cache({.Draw, .Clickable, .Active_Animation, .Draw_Text, .Hot_Animation}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}
// Same as text_container_absolute, but for text buttons.
text_button_absolute :: proc(id_string: string, x, y: f32, metadata: Box_Metadata = {}) -> Box_Signals {
	name := get_name_from_id_string(id_string)
	length := f32(word_rendered_length(name, ui_state.font_size))
	height := tallest_rendered_char(name, ui_state.font_size)
	rect := Rect{{x, y}, {x + length, y + height}}
	b := box_from_cache({.Draw, .Clickable, .Active_Animation, .Draw_Text, .Hot_Animation}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

// Differs from text_container as it's like <input> element from HTML.
text_box :: proc(id_string: string, rect: Rect, metadata: Box_Metadata = {}) -> Box_Signals {
	data: string // might need to allocte this.
	b := box_from_cache({.Draw, .Clickable, .Draw_Text}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

num_input :: proc(
	id_string: string,
	rect: Rect,
	min, max: int,
	metadata: Box_Metadata = {},
	init_value: int = 0,
) -> Box_Signals {
	b := box_from_cache(
		{.Draw, .Draw_Text, .Edit_Text, .Text_Left, .Clickable, .Draw_Border},
		tprintf("{}-text-input", id_string),
		rect,
		metadata,
	)

	buffer_to_use: string
	tmp_buffer: [128]byte
	// We default to box.value as a string for num inputs, because otherwise, what should the default value be ?
	// 0 can't be a default value since it's meaningfull; instead we just use the empty string.
	if b.value == nil {
		b.value = strconv.itoa(tmp_buffer[:], init_value)
	}
	switch _ in b.value.? {
	case string:
		buffer_to_use = b.value.?.(string)
	case u32:
		buffer_to_use = strconv.itoa(tmp_buffer[:], int(b.value.?.(u32)))
	}
	signals := box_signals(b)
	// builder := str.builder_make(context.temp_allocator)
	builder := str.builder_make()
	state: edit.State

	// Not sure if generating a unique ID is neccessary, but we shall do it anyway for now.
	bytes_buffer: bytes.Buffer
	defer bytes.buffer_destroy(&bytes_buffer)
	bytes.buffer_init_string(&bytes_buffer, id_string)
	byts := bytes.buffer_to_bytes(&bytes_buffer)
	editor_id := u64(hash.crc32(byts))

	edit.init(&state, context.temp_allocator, context.temp_allocator)
	edit.setup_once(&state, &builder)
	edit.begin(&state, editor_id, &builder)
	edit.input_text(&state, buffer_to_use)

	edit.move_to(&state, .Start)
	for i: u32 = 0; i < b.cursor_pos; i += 1 {edit.move_to(&state, .Right)}

	if app.ui_state.last_active_box == b {
		i: u32 = 0
		for i = 0; i < app.curr_chars_stored; i += 1 {
			keycode := app.char_queue[i]
			#partial switch keycode {
			case .LEFT:
				edit.move_to(&state, .Left)
			case .RIGHT:
				edit.move_to(&state, .Right)
			case .BACKSPACE:
				edit.delete_to(&state, .Left)
			case .DELETE:
				edit.delete_to(&state, .Right)
			case .LCTRL | .RCTRL:
			case .ESCAPE, .CAPSLOCK:
				ui_state.last_active_box = nil
				ui_state.active_box = nil
				app.curr_chars_stored = 1
				break
			case .UP, .k:
				len := len(state.builder.buf)
				new_num := strconv.atoi(str.to_string(builder)) + 1
				if new_num > max {
					new_num = max
				}
				buf: [4]u8
				new_value := strconv.itoa(buf[:], new_num)
				edit.move_to(&state, .Start)
				edit.select_to(&state, .End)
				edit.selection_delete(&state)
				edit.input_text(&state, new_value)
			case .DOWN, .j:
				len := len(state.builder.buf)
				new_num := strconv.atoi(str.to_string(builder)) - 1
				if new_num < min {
					new_num = min
				}
				buf: [4]u8
				new_value := strconv.itoa(buf[:], new_num)
				edit.move_to(&state, .Start)
				edit.select_to(&state, .End)
				edit.selection_delete(&state)
				edit.input_text(&state, new_value)
			case:
				ch := rune(keycode)
				if unicode.is_number(ch) {
					edit.input_rune(&state, rune(keycode))
				}
			}
		}
		app.curr_chars_stored = 0
	}

	b.value = str.to_string(state.builder^)
	append(&ui_state.temp_boxes, b)
	res := Text_Input_Signals {
		box_signals = signals,
		new_string  = b.value.?.(string),
		cursor_pos  = state.selection.x,
	}
	b.cursor_pos = u32(res.cursor_pos)
	edit.end(&state)
	return signals
}

text_input :: proc(id_string: string, rect: Rect, metadata: Box_Metadata = {}) -> Box_Signals {
	box := box_from_cache(
		{.Draw, .Draw_Text, .Edit_Text, .Text_Left, .Clickable, .Draw_Border},
		tprintf("{}-text-input", id_string),
		rect,
		metadata,
	)
	signals := box_signals(box)

	if box.value == nil {
		box.value = ""
	}

	buffer_to_use := box.value.?.(string)
	builder := str.builder_make()
	state: edit.State

	// Not sure if generating a unique ID is neccessary, but we shall do it anyway for now.
	bytes_buffer: bytes.Buffer
	defer bytes.buffer_destroy(&bytes_buffer)
	bytes.buffer_init_string(&bytes_buffer, id_string)
	byts := bytes.buffer_to_bytes(&bytes_buffer)
	editor_id := u64(hash.crc32(byts))

	edit.init(&state, context.temp_allocator, context.temp_allocator)
	edit.setup_once(&state, &builder)
	edit.begin(&state, editor_id, &builder)
	edit.input_text(&state, buffer_to_use)

	// If clicked on a new textbox just put cursor at the end, else put it where it was at the end of the last frame.
	if box != ui_state.last_active_box {
		edit.move_to(&state, .End)
	} else {
		// Put cursor where it was last frame
		edit.move_to(&state, .Start)
		for i: u32 = 0; i < box.cursor_pos; i += 1 {edit.move_to(&state, .Right)}
	}

	if app.ui_state.last_active_box == box {
		i: u32 = 0
		for i = 0; i < app.curr_chars_stored; i += 1 {
			keycode := app.char_queue[i]
			#partial switch keycode {
			case .LEFT:
				edit.move_to(&state, .Left)
			case .RIGHT:
				edit.move_to(&state, .Right)
			case .BACKSPACE:
				edit.delete_to(&state, .Left)
			case .DELETE:
				edit.delete_to(&state, .Right)
			case .LCTRL | .RCTRL:
			//do nothing
			case .ESCAPE, .CAPSLOCK:
				ui_state.last_active_box = nil
				ui_state.active_box = nil
				app.curr_chars_stored = 1
				break
			case .UP:
				if val, is_pitch_step := metadata.(Step_Metadata); is_pitch_step {
					if val.step_type == .Pitch_Note {
						new_value := up_one_semitone(str.to_string(builder))
						edit.move_to(&state, .Start)
						edit.select_to(&state, .End)
						edit.selection_delete(&state)
						edit.input_text(&state, new_value)
					}
				}
			case .DOWN:
				if val, is_pitch_step := metadata.(Step_Metadata); is_pitch_step {
					if val.step_type == .Pitch_Note {
						new_value := down_one_semitone(str.to_string(builder))
						edit.move_to(&state, .Start)
						edit.select_to(&state, .End)
						edit.selection_delete(&state)
						edit.input_text(&state, new_value)
					}
				}
			case:
				ch := rune(keycode)
				if unicode.is_alpha(ch) || unicode.is_digit(ch) {
					edit.input_rune(&state, ch)
				}
			}
		}
		// We do this because not every key should be handled by the text input.
		// For example, the escape key, should remove focus from the current text box,
		// but NOT be consumed, and instead be consumed elsewhere in the UI.
		app.curr_chars_stored -= app.curr_chars_stored - i
	}

	box.value = str.to_string(state.builder^)
	append(&ui_state.temp_boxes, box)
	res := Text_Input_Signals {
		box_signals = signals,
		new_string  = box.value.?.(string),
		cursor_pos  = state.selection[0],
	}
	box.cursor_pos = u32(res.cursor_pos)

	// str.builder_destroy(&builder)
	edit.end(&state)
	edit.destroy(&state)
	// return res
	return signals
}

up_one_semitone :: proc(curr_note: string) -> string {
	if len(curr_note) < 2 {
		return curr_note
	}
	curr_value, _ := str.to_upper(curr_note, context.temp_allocator)
	is_sharp := str.contains(curr_value, "#")
	octave := is_sharp ? strconv.atoi(curr_value[2:]) : strconv.atoi(curr_value[1:])
	new_value: string
	switch curr_value[0] {
	case 'A':
		new_value = is_sharp ? tprintf("B{}", octave) : tprintf("A#{}", octave)
	case 'B':
		new_value = tprintf("C{}", octave)
	case 'C':
		new_value = is_sharp ? tprintf("D{}", octave) : tprintf("C#{}", octave)
	case 'D':
		new_value = is_sharp ? tprintf("E{}", octave) : tprintf("D#{}", octave)
	case 'E':
		new_value = tprintf("F{}", octave)
	case 'F':
		new_value = is_sharp ? tprintf("G{}", octave) : tprintf("F#{}", octave)
	case 'G':
		new_value = is_sharp ? tprintf("A{}", octave + 1) : tprintf("G#{}", octave)
	case:
		panic("fuck1")
	}
	return new_value
}

down_one_semitone :: proc(curr_note: string) -> string {
	curr_value := str.to_upper(curr_note, context.temp_allocator)
	is_sharp := str.contains(curr_value, "#")
	octave := is_sharp ? strconv.atoi(curr_value[2:]) : strconv.atoi(curr_value[1:])
	new_value: string

	switch curr_value[0] {
	case 'A':
		new_value = is_sharp ? tprintf("A{}", octave) : tprintf("G#{}", octave - 1)
	case 'B':
		new_value = tprintf("A#{}", octave)
	case 'C':
		new_value = is_sharp ? tprintf("C{}", octave) : tprintf("B{}", octave)
	case 'D':
		new_value = is_sharp ? tprintf("D{}", octave) : tprintf("C#{}", octave)
	case 'E':
		new_value = tprintf("D#{}", octave)
	case 'F':
		new_value = is_sharp ? tprintf("F{}", octave) : tprintf("E{}", octave)
	case 'G':
		new_value = is_sharp ? tprintf("G{}", octave) : tprintf("F#{}", octave)
	case:
		panic("fuck1")
	}
	return new_value
}
