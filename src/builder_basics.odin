// Builder basics, buttons, containers, etc.
package main
import "core:bytes"
import "core:hash"
import "core:math"
import "core:math/rand"
import str "core:strings"
import "core:text/edit"
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

container :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache({}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

draggable_container :: proc(id_string: string, rect: ^Rect) -> Draggable_Container_Signals {
	handle_bar_rect := cut_rect(rect, RectCut{side = .Top, size = {.Percent, 0.1}})
	handle_bar := text_button(tprintf("drag-me@{}-handle-bar", id_string), handle_bar_rect)
	b := box_from_cache({.Floating_X, .Draw}, id_string, rect^)
	append(&ui_state.temp_boxes, b)
	return Draggable_Container_Signals{handle_bar = handle_bar, container = box_signals(b)}
}

text_container :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache({.Draw_Text}, id_string, rect)
	b.color = {1, 1, 1, 1}
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

// Lets you draw a text container at an absolute x,y position and calculates size
// based on the font.
text_container_absolute :: proc(id_string: string, x, y: f32) -> Box_Signals {
	name := get_name_from_id_string(id_string)
	length := f32(word_rendered_length(name))
	height := f32(tallest_char_height(name))
	rect := Rect{{x, y}, {x + length, y + height}}
	b := box_from_cache({.Draw_Text}, id_string, rect)
	b.color = {1, 1, 1, 1}
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

button :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache({.Draw, .Clickable, .Active_Animation, .Hot_Animation}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

text_button :: proc(id_string: string, rect: Rect) -> Box_Signals {
	b := box_from_cache(
		{.Draw, .Clickable, .Active_Animation, .Draw_Text, .Hot_Animation},
		id_string,
		rect,
	)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

// Same as text_container_absolute, but for text buttons.
text_button_absolute :: proc(id_string: string, x, y: f32) -> Box_Signals {
	name := get_name_from_id_string(id_string)
	length := f32(word_rendered_length(name))
	height := f32(tallest_char_height(name))
	rect := Rect{{x, y}, {x + length, y + height}}
	b := box_from_cache(
		{.Draw, .Clickable, .Active_Animation, .Draw_Text, .Hot_Animation},
		id_string,
		rect,
	)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

// Differs from text_container as it's like <input> element from HTML.
text_box :: proc(id_string: string, rect: Rect) -> Box_Signals {
	data: string // might need to allocte this.
	b := box_from_cache({.Draw, .Clickable, .Draw_Text}, id_string, rect)
	append(&ui_state.temp_boxes, b)
	return box_signals(b)
}

text_input :: proc(id_string: string, rect: Rect, buffer: string) -> Text_Input_Signals {
	// could probably change the api of this function in order to avoid this messyness.
	b := box_from_cache(
		{.Draw, .Draw_Text, .Edit_Text, .Text_Left, .Clickable, .Draw_Border},
		tprintf("{}-text-input", id_string),
		rect,
		buffer,
	)
	buffer_to_use := b.name == "" ? buffer : b.name
	signals := box_signals(b)
	builder := str.builder_make()
	state: edit.State

	// Not sure if generating a unique ID is neccessary, but we shall do it anyway
	// for now.
	bytes_buffer: bytes.Buffer
	defer bytes.buffer_destroy(&bytes_buffer)
	bytes.buffer_init_string(&bytes_buffer, id_string)
	byts := bytes.buffer_to_bytes(&bytes_buffer)
	editor_id := u64(hash.crc32(byts))
	// printfln("editor id for box: %v is %v", id_string, editor_id)

	edit.init(&state, context.temp_allocator, context.temp_allocator)
	edit.setup_once(&state, &builder)
	edit.begin(&state, editor_id, &builder)
	edit.input_text(&state, buffer_to_use)

	// Put cursor where it was last frame
	diff := len(buffer_to_use) - app.ui_state.text_cursor_pos
	diff = diff > 0 ? diff : diff * -1

	for i := 0; i < diff; i += 1 {edit.move_to(&state, .Left)}

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
			//do nothing
			case .ESCAPE, .CAPSLOCK:
				ui_state.last_active_box = nil
				ui_state.active_box = nil
				app.curr_chars_stored = 1
				break
			case .UP, .DOWN:
			// consuming these events
			case:
				edit.input_rune(&state, rune(keycode))
			}
		}
		// We do this because not every key should be handled by the text input.
		// For example, the escape key, should remove focus from the current text box,
		// but NOT be consumed, and instead be consumed elsewhere in the UI.
		app.curr_chars_stored -= app.curr_chars_stored - i
	}

	// Kind of jank, but this is how we differentiate

	b.name = str.to_string(state.builder^)
	append(&ui_state.temp_boxes, b)
	res := Text_Input_Signals {
		box_signals = signals,
		new_string  = b.name,
		// Need to be careful here.
		cursor_pos  = state.selection[0],
	}
	app.ui_state.text_cursor_pos = res.cursor_pos
	app.ui_state.text_cursor_x_coord =
		rect.top_left.x +
		f32(app.ui_state.text_box_padding) +
		f32(word_rendered_length(res.new_string[:res.cursor_pos]))
	edit.end(&state)
	return res
}
