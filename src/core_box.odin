/* 
Code to handle 'boxes' which are essentially the most fundamental logical
building block of the UI; following Ryan Fleury's UI methods.
Basic rectcut code is from here: https://halt.software/p/rectcut-for-dead-simple-ui-layouts,
but it seems broken, so I kind of implemented my own.
*/
package main
import "base:intrinsics"
import "core:crypto/hash"
import "core:fmt"
import "core:math"
import "core:math/fixed"
import "core:math/rand"
import "core:strings"
import sdl "vendor:sdl2"


Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

Box_Cache :: map[string]^Box

SizeKind :: enum {
	Pixels,
	Percent,
}

Size :: struct {
	kind:  SizeKind,
	value: f32,
}

Rect :: struct {
	top_left:     Vec2,
	bottom_right: Vec2,
}

RectCutSide :: enum {
	Left,
	Right,
	Top,
	Bottom,
}

RectCut :: struct {
	size: Size,
	side: RectCutSide,
}

Box_Flag :: enum {
	Clickable,
	Scrollable,
	View_Scroll,
	Draw,
	Draw_Text,
	Edit_Text,
	Draw_Border,
	Draw_Background,
	Draw_Drop_Shadow,
	Clip,
	Hot_Animation,
	Active_Animation,
	Draggable,
	Fixed_Width,
	Floating_X,
	No_Offset, // 
}

Box_Flags :: bit_set[Box_Flag]

Box_Signals :: struct {
	box:            ^Box,
	mouse:          Vec2,
	clicked:        bool,
	double_clicked: bool,
	right_clicked:  bool,
	pressed:        bool,
	released:       bool,
	right_pressed:  bool,
	right_released: bool,
	dragging:       bool,
	dragged_over:   bool,
	hovering:       bool,
	scrolled:       bool,
}

// New Box struct based on my simplified layout algorithm.
Box :: struct {
	// UI info - color, padding, visual names, etc
	name:                     string,
	color:                    [4]f32,
	padding:                  [4]Size, // {x-left, x-right, y-bottom, y-top}

	// Caching related data.
	hash_next:                ^Box,
	hash_prev:                ^Box,
	// Key + generation info.
	key:                      string,
	last_frame_touched_index: u64,

	// Per-frame info provided by builders
	flags:                    Box_Flags,
	id_string:                string,

	// The actual (x1,y1),(x2,y2) co-ordinates of the box on the screen.
	rect:                     Rect,
	// Actual pixel (width, height) dimensions of the box.
	size:                     Vec2,
	visible:                  bool,
	corner_radius:            f32,

	// Persistent data.
	hot:                      bool,
	active:                   bool,

	// Feels a little wrong having this here, but let's try
	signals:                  Box_Signals,

	// To help determine if various things in the ui are selected.
	selected:                 bool,

	// Helps determine event handling when items are stacked on each other.
	z_index:                  u8,
}

box_from_cache :: proc(flags: Box_Flags, id_string: string, rect: Rect) -> ^Box {
	if id_string in ui_state.box_cache {
		box := ui_state.box_cache[id_string]
		box.rect = rect
		return box
	} else {
		printf("making new box: {}", id_string)
		new_box := box_make(flags, id_string, rect)
		ui_state.box_cache[id_string] = new_box
		return new_box
	}
}

box_make :: proc(flags: Box_Flags, id_string: string, rect: Rect) -> ^Box {
	// println("making new box: ", id_string)
	box := new(Box)
	box.flags = flags
	box.id_string = id_string
	box.color = {rand.float32_range(0, 1), rand.float32_range(0, 1), rand.float32_range(0, 1), 1}
	color, is_top := top_color()
	if !is_top {
		println("[WARNING] - There was no color assigned to this box, it's color is randomised.")
		box.color = {rand.float32_range(0, 1), rand.float32_range(0, 1), rand.float32_range(0, 1), 1}
	} else {
		println("top color was: ", color)
		box.color = color
	}
	box.name = get_name_from_id_string(id_string)
	box.rect = rect
	box.z_index = ui_state.z_index
	return box
}


box_signals :: proc(box: ^Box) -> Box_Signals {
	// signals from previous frame
	prev_signals := box.signals
	signals: Box_Signals
	signals.box = box
	signals.hovering = hovering_in_box(box)
	if signals.hovering {
		ui_state.hot_box = box
		signals.pressed = app.mouse.left_pressed
		if pressed_on_box(box, prev_signals) {
			ui_state.active_box = box
			signals.clicked = true
		}
		if app.mouse.wheel.x != 0 || app.mouse.wheel.y != 0 {
			println("scrolling on ", box.id_string)
			signals.scrolled = true
		}
		if signals.pressed {
			signals.dragged_over = true
			if prev_signals.pressed {
				// println("dragging: ", box.name)
				signals.dragging = true
			}
		}
	}
	box.signals = signals
	return signals
}

// Does expected checking, but also accounts for z-index stuff.
hovering_in_box :: proc(box: ^Box) -> bool {
	if ui_state.hot_box != nil {
		if box.z_index > ui_state.hot_box.z_index {
			if mouse_inside_box(box, {app.mouse.pos.x, app.mouse.pos.y}) && .Clickable in box.flags {
				ui_state.hot_box.hot = false
				ui_state.hot_box.signals.hovering = false
				return true
			}
		}
		return false
	}
	return mouse_inside_box(box, {app.mouse.pos.x, app.mouse.pos.y}) && .Clickable in box.flags
}

// Does expected checking, but also accounts for z-index stuff.
pressed_on_box :: proc(box: ^Box, prev_signals: Box_Signals) -> bool {
	if ui_state.active_box != nil {
		if box.z_index > ui_state.active_box.z_index {
			// might need to add more here
			if prev_signals.pressed && !app.mouse.left_pressed && .Clickable in box.flags {
				ui_state.active_box.active = false
				ui_state.active_box.signals.clicked = false
				ui_state.active_box.signals.pressed = false
				ui_state.active_box.selected = false
				return true
			}
		}
		return false
	}
	return prev_signals.pressed && !app.mouse.left_pressed && ui_state.active_box == nil && .Clickable in box.flags
}

rect_from_points :: proc(a, b: Vec2) -> sdl.Rect {
	width := cast(i32)abs(a.x - b.x)
	height := cast(i32)abs(a.y - b.y)
	return sdl.Rect{w = width, h = height, x = cast(i32)a.x, y = cast(i32)a.y}
}

cut_rect :: proc(rect: ^Rect, rect_cut: RectCut) -> Rect {
	switch rect_cut.side {
	case .Left:
		return cut_left(rect, rect_cut.size)
	case .Right:
		return cut_right(rect, rect_cut.size)
	case .Top:
		return cut_top(rect, rect_cut.size)
	case .Bottom:
		return cut_bottom(rect, rect_cut.size)
	}
	panic("[!] cut_rect: invalid side")
}

cut_left :: proc(rect: ^Rect, amount: Size) -> Rect {
	parent_top_left_x: f32 = rect.top_left.x
	px_amount := math.floor(get_amount(rect^, amount, .Left))
	rect.top_left.x = rect.top_left.x + px_amount
	return Rect{top_left = {parent_top_left_x, rect.top_left.y}, bottom_right = {parent_top_left_x + px_amount, rect.bottom_right.y}}
}
cut_right :: proc(rect: ^Rect, amount: Size) -> Rect {
	parent_bottom_right_x: f32 = rect.bottom_right.x
	px_amount := math.floor(get_amount(rect^, amount, .Right))
	rect.bottom_right.x = rect.bottom_right.x - px_amount
	return Rect {
		top_left = {parent_bottom_right_x - px_amount, rect.top_left.y},
		bottom_right = {parent_bottom_right_x, rect.bottom_right.y},
	}
}
cut_top :: proc(rect: ^Rect, amount: Size) -> Rect {
	parent_top_left_y: f32 = rect.top_left.y
	px_amount := math.floor(get_amount(rect^, amount, .Top))
	rect.top_left.y = rect.top_left.y + px_amount
	return Rect{{rect.top_left.x, parent_top_left_y}, {rect.bottom_right.x, parent_top_left_y + px_amount}}
}
cut_bottom :: proc(rect: ^Rect, amount: Size) -> Rect {
	parent_bottom_right_y: f32 = rect.bottom_right.y
	px_amount := math.floor(get_amount(rect^, amount, .Bottom))
	rect.bottom_right.y = rect.bottom_right.y - px_amount
	return Rect{{rect.top_left.x, parent_bottom_right_y - px_amount}, {rect.bottom_right.x, parent_bottom_right_y}}
}

// All the get_* functions, return the desired rectangle, without cutting
// the source rectangle.
get_rect :: proc(rect: Rect, rect_cut: RectCut) -> Rect {
	switch rect_cut.side {
	case .Left:
		return get_left(rect, rect_cut.size)
	case .Right:
		return get_right(rect, rect_cut.size)
	case .Top:
		return get_top(rect, rect_cut.size)
	case .Bottom:
		return get_bottom(rect, rect_cut.size)
	}
	panic("[!] cut_rect: invalid side")
}
get_left :: proc(rect: Rect, amount: Size) -> Rect {
	parent_top_left_x: f32 = rect.top_left.x
	px_amount := math.floor(get_amount(rect, amount, .Left))
	return Rect{top_left = {parent_top_left_x, rect.top_left.y}, bottom_right = {parent_top_left_x + px_amount, rect.bottom_right.y}}
}
get_right :: proc(rect: Rect, amount: Size) -> Rect {
	parent_bottom_right_x: f32 = rect.bottom_right.x
	px_amount := math.floor(get_amount(rect, amount, .Right))
	return Rect {
		top_left = {parent_bottom_right_x - px_amount, rect.top_left.y},
		bottom_right = {parent_bottom_right_x, rect.bottom_right.y},
	}
}
get_top :: proc(rect: Rect, amount: Size) -> Rect {
	parent_top_left_y: f32 = rect.top_left.y
	px_amount := math.floor(get_amount(rect, amount, .Top))
	return Rect{{rect.top_left.x, parent_top_left_y}, {rect.bottom_right.x, parent_top_left_y + px_amount}}
}
get_bottom :: proc(rect: Rect, amount: Size) -> Rect {
	parent_bottom_right_y: f32 = rect.bottom_right.y
	px_amount := math.floor(get_amount(rect, amount, .Bottom))
	return Rect{{rect.top_left.x, parent_bottom_right_y - px_amount}, {rect.bottom_right.x, parent_bottom_right_y}}
}

// add_* lets you add to a rectangle, using same sizing semantics as when cutting.
add_left :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_amount(rect, amount, .Left))
	new_rect := rect
	new_rect.top_left.x = rect.top_left.x - px_amount
	return new_rect
}
add_right :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_amount(rect, amount, .Right))
	new_rect := rect
	new_rect.bottom_right.x = rect.bottom_right.x + px_amount
	return new_rect
}
add_top :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_amount(rect, amount, .Top))
	new_rect := rect
	new_rect.top_left.y = rect.top_left.y - px_amount
	return new_rect
}
add_bottom :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_amount(rect, amount, .Bottom))
	new_rect := rect
	new_rect.bottom_right.y = rect.bottom_right.y + px_amount
	return new_rect
}

// Let's you add pixels in a specific direction.
expand_x :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_amount(rect, amount, .Left))
	new_rect := rect
	new_rect.top_left.x = rect.top_left.x - px_amount
	new_rect.bottom_right.x = rect.bottom_right.x + px_amount
	return new_rect
}
expand_y :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_amount(rect, amount, .Top))
	new_rect := rect
	new_rect.top_left.y = rect.top_left.y - px_amount
	new_rect.bottom_right.y = rect.bottom_right.y + px_amount
	return new_rect
}
expand :: proc(rect: Rect, amount: Size) -> Rect {
	return expand_x(expand_y(rect, amount), amount)
}

// Let's you remove pixels in a specific direction
shrink_x :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_amount(rect, amount, .Left))
	new_rect := rect
	new_rect.top_left.x = rect.top_left.x + px_amount
	new_rect.bottom_right.x = rect.bottom_right.x - px_amount
	return new_rect
}
shrink_y :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_amount(rect, amount, .Left))
	new_rect := rect
	new_rect.top_left.y = rect.top_left.y - px_amount
	new_rect.bottom_right.y = rect.bottom_right.y + px_amount
	return new_rect
}
shrink :: proc(rect: Rect, amount: Size) -> Rect {
	return shrink_x(shrink_y(rect, amount), amount)
}

// Calulcates actual pixel amount based on abstract size.
get_amount :: proc(rect: Rect, amount: Size, side: RectCutSide) -> f32 {
	switch amount.kind {
	case .Percent:
		switch side {
		case .Left, .Right:
			return amount.value * (rect.bottom_right.x - rect.top_left.x)
		case .Top, .Bottom:
			return amount.value * (rect.bottom_right.y - rect.top_left.y)
		}
	case .Pixels:
		return amount.value
	}
	panic("[!] get_amount: invalid kind")
}

// // Doesn't account for padding or anything like that.
// calculate_text_size :: proc(char_map: map[rune]Character, text: string) -> Vec2 {
// 	width, height: f32 = 0, 0
// 	for c in text {
// 		character := char_map[c]
// 		width += character.size[0]
// 		println("this char", character, "has width:", character.size[0])
// 		height = max(height, character.size[1])
// 	}
// 	return Vec2{width, height}
// }

mouse_inside_box :: proc(box: ^Box, mouse: [2]i32) -> bool {
	mousex := cast(f32)mouse.x
	mousey := cast(f32)mouse.y
	return(
		mousex >= box.rect.top_left.x &&
		mousex <= box.rect.bottom_right.x &&
		mousey >= box.rect.top_left.y &&
		mousey <= box.rect.bottom_right.y \
	)
}


push_color :: proc(color: Color) {
	// println("pushign color:", color)
	append(&ui_state.color_stack, color)
}

pop_color :: proc() -> Color {
	if len(ui_state.color_stack) < 1 {
		panic("Tried to pop off empty color stack")
	}
	return pop(&ui_state.color_stack)
}

top_color :: proc() -> (Color, bool) {
	n_colors := len(ui_state.color_stack)
	if n_colors < 1 do return {20, 20, 20, 20}, false
	return ui_state.color_stack[n_colors - 1], true
}
set_box_top_side_color :: proc(box: ^Box, colors: [2]f32) {
	box.color[0] = colors[0]
	box.color[3] = colors[1]
}

set_box_bottom_side_color :: proc(box: ^Box, colors: [2]f32) {
	box.color[1] = colors[0]
	box.color[2] = colors[1]
}
set_box_color :: proc(box: ^Box, color: [4]f32) {
	box.color = color
}

set_box_single_color :: proc(box: ^Box, color: f32) {
	box.color = {color, color, color, 1}
}

top_rect :: proc() -> ^Rect {
	return ui_state.rect_stack[len(ui_state.rect_stack) - 1]
}
push_parent_rect :: proc(rect: ^Rect) {
	append(&ui_state.rect_stack, rect)
}
pop_parent_rect :: proc() {
	pop(&ui_state.rect_stack)
}
get_name_from_id_string :: proc(id_string: string) -> string {
	to := strings.index(id_string, "@")
	return id_string[:to]
}
get_id_from_id_string :: proc(id_string: string) -> string {
	from := strings.index(id_string, "@")
	return id_string[from:]
}

spacer :: proc(id_string: string, rect_cut: RectCut) -> ^Box {
	rect := cut_rect(top_rect(), rect_cut)
	s := box_from_cache({.Draw}, id_string, rect)
	append(&ui_state.temp_boxes, s)
	return s
}
