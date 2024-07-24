// Code to handle 'boxes' which are essentially the most fundamental logical
// building block of the UI; following Ryan Fleury's UI methods.

package ui_core
import "base:intrinsics"
import "core:fmt"
import "core:math/fixed"
import sdl "vendor:sdl2"
println :: fmt.println

// Absolute value
abs :: proc(x: $T) -> T where intrinsics.type_is_numeric(T) {
	return x if x >= 0 else -1 * x
}
Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

Box_Cache :: map[string]^Box

Key :: struct {
	data: string,
}

SizeKind :: enum {
	None,
	Pixels,
	Text_Content,
	Pecent_Of_Parent,
	Children_Sum,
}
Size :: struct {
	kind:       SizeKind,
	value:      f32,
	strictness: f32,
}
Axis :: enum {
	X = 0,
	Y = 1,
}

Box_Flag :: enum {
	Clickable,
	Scrollable,
	View_Scroll,
	Draw,
	Draw_Text,
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
	dragging:       bool,
	hovering:       bool,
	scrolled:       bool,
}

// The layout data is named poorly imo, since I've copied Ryan. When my
// version is working, I should rename them more sensibly.
Box :: struct {
	// Data to navigate the UI tree.
	first:                    ^Box,
	last:                     ^Box,
	next:                     ^Box,
	prev:                     ^Box,
	parent:                   ^Box,
	n_children:               u32,

	// color
	color:                    [4]f32,
	padding:                  [4]Size, // {x-left, x-right, y-bottom, y-top}

	// Caching related data.
	hash_next:                ^Box,
	hash_prev:                ^Box,
	// Key + generation info.
	key:                      Key,
	last_frame_touched_index: u64,

	// Per-frame info provided by builders
	flags:                    Box_Flags,
	pref_size:                [2]Size, // desired size
	child_layout_axis:        Axis,
	id_string:                string,
	// semantic_size:            [2]Size, // along x and/or y

	// post-size-algo layout data
	calc_size:                Vec2,
	calc_rel_pos:             Vec2,

	// post-layout-algo layout data
	rel_rect:                 [2]Vec2,
	rect:                     [2]Vec2,
	// rel_corner_delta:		  Vec2,
	visible:                  bool,

	// Persistent data
	hot:                      bool,
	active:                   bool,
}


box_from_cache :: proc(
	flags: Box_Flags,
	ui_state: ^UI_State,
	id_string: string,
	size: [2]Size,
) -> ^Box {
	if id_string in ui_state.box_cache {
		box := ui_state.box_cache[id_string]
		return box
	} else {
		println("creating new box: ", id_string)
		new_box := box_make(flags, ui_state, id_string, size)
		ui_state.box_cache[id_string] = new_box
		new_box.parent.n_children += 1
		return new_box
	}
}

box_set_tree_links :: proc(ui_state: ^UI_State, box: ^Box) {
	box.parent = ui_state.layout_stack[len(ui_state.layout_stack) - 1]
	if box.parent.first == nil {
		box.parent.first = box
		box.parent.last = box
	} else {
		box.parent.last.next = box
		box.prev = box.parent.last
		box.parent.last = box
	}
}

// this is not actually how this function signature will ultimately be
box_make :: proc(
	flags: Box_Flags,
	ui_state: ^UI_State,
	id_string: string,
	size: [2]Size,
) -> ^Box { 	// rect_size: [2]Vec2,
	box := new(Box)
	box.flags = flags
	box.id_string = id_string
	box.hot = false
	box.color = {1, 0.5, 0.2, 1}
	box.pref_size = size
	box_set_tree_links(ui_state, box)
	return box
}

mouse_inside_box :: proc(box: ^Box, mouse: Vec2) -> bool {
	return(
		mouse.x >= box.rect[0].x &&
		mouse.x <= box.rect[1].x &&
		mouse.y >= box.rect[0].y &&
		mouse.y <= box.rect[1].y \
	)
}

rect_from_points :: proc(a, b: Vec2) -> sdl.Rect {
	width := cast(i32)abs(a.x - b.x)
	height := cast(i32)abs(a.y - b.y)
	return sdl.Rect{w = width, h = height, x = cast(i32)a.x, y = cast(i32)a.y}
}

box_signals :: proc(ui_state: UI_State, box: ^Box) -> Box_Signals {
	signals: Box_Signals
	signals.box = box

	mouseX, mouseY: i32
	sdl.GetMouseState(&mouseX, &mouseY)
	signals.hovering = mouse_inside_box(box, Vec2{cast(f32)mouseX, cast(f32)mouseY})

	if signals.hovering {
		signals.clicked = ui_state.mouse.left_pressed
		signals.right_clicked = ui_state.mouse.right_pressed
		if ui_state.mouse.wheel.x != 0 || ui_state.mouse.wheel.y != 0 {
			signals.scrolled = true
		}
	}
	return signals
}
