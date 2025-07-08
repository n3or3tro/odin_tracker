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
import "core:mem"
import "core:strings"
import s "core:strings"
import "core:time"
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
	Text_Center,
	Text_Left,
	Text_Right,
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

// Box-specific metadata, the idea here is: we were using id_strings to hold too much information.
// It was a non type safe, slow-to-parse, way of storing this info that should just be stored on the box.
// However, as a general rule we want to keep the UI core relatively small and simple, so don't want to 
// implement all application state via this mechanism - this is a tricky design tradeoff, that may require
// further refactoring in the future.
Box_Metadata :: union #no_nil {
	No_Metadata,
	Step_Metadata,
	Track_Control_Metadata,
	Sampler_Metadata,
}

No_Metadata :: struct {}

Step_Metadata :: struct {
	track_num: u32,
	step_num:  u32,
	step_type: Track_Step_Part,
}
Track_Control_Metadata :: struct {
	track_num:    u32,
	control_type: enum {
		// Sometimes all you want is the track_number.
		Irrelevant,
		Volume_Slider,
		Enable_Button,
		File_Load_Button,
		BPM_Input,
	},
}

Sampler_Metadata :: struct {
	track_num:    u32,
	sampler_part: enum {
		Waveform,
		Slice_Marker,
		ADSR_Knob,
		Mode_Button,
	},
	slice_num:    Maybe(u32), // For slice markers
}


Step_Value_Type :: union {
	string, // pitch.
	u32, // volume, send.s
}


// New Box struct based on my simplified layout algorithm.
Box :: struct {
	// UI info - color, padding, visual names, etc
	name:          string,
	color:         [4]f32,
	padding:       [4]Size, // {x-left, x-right, y-bottom, y-top}

	// Caching related data.
	// hash_next:                ^Box,
	// hash_prev:                ^Box,
	// // Key + generation info.
	// key:                      string,
	// last_frame_touched_index: u64,

	// Per-frame info provided by builders
	flags:         Box_Flags,
	id_string:     string,
	// Might need to generalise the type of value more in the future. ATM, this assumes
	// that the only boxes with explicit values are tracker steps.
	value:         Maybe(Step_Value_Type),
	// Considering wrapping this in a Maybe(), but should be okay for now.
	font_size:     Font_Size,


	// The actual (x1,y1),(x2,y2) co-ordinates of the box on the screen.
	rect:          Rect,
	// Actual pixel (width, height) dimensions of the box.
	size:          Vec2,
	visible:       bool,
	corner_radius: f32,

	// The three are neccessary I think in order to have simultaneous keyboard and mouse
	// control of tracker steps.
	hot:           bool,
	active:        bool,
	// I think selected is only relevant for tracker steps.
	selected:      bool,

	// Feels a little wrong having this here, but let's try
	signals:       Box_Signals,

	// Helps determine event handling when items are stacked on each other.
	z_index:       u8,

	// Wasn't sure whether to add this or not, but basically I think it will be more helpful than messy,
	// I.e. rather than always parsing id_string's, we'll store metadata when relevant.
	metadata:      Box_Metadata,
}

box_from_cache :: proc(
	flags: Box_Flags,
	id_string: string,
	rect: Rect,
	metadata: Box_Metadata = {},
) -> ^Box {
	if id_string in ui_state.box_cache {
		box := ui_state.box_cache[id_string]
		box.rect = rect
		// Not sure if this is neccessary.
		// box.metadata = metadata
		return box
	} else {
		persistant_id_string := s.clone(id_string)
		new_box := box_make(flags, persistant_id_string, rect, metadata)
		if id_string != "spacer@spacer" {
			ui_state.box_cache[persistant_id_string] = new_box
			printfln("creating new box with id_string: {}", id_string)
		}
		return new_box
	}
}

box_make :: proc(flags: Box_Flags, id_string: string, rect: Rect, metadata: Box_Metadata = {}) -> ^Box {
	box := new(Box)
	box.flags = flags
	box.id_string = id_string
	box.color = {rand.float32_range(0, 1), rand.float32_range(0, 1), rand.float32_range(0, 1), 1}
	color, is_top := top_color()
	if !is_top {
		// println("[WARNING] - There was no color assigned to this box, it's color is randomised.")
		box.color = {rand.float32_range(0, 1), rand.float32_range(0, 1), rand.float32_range(0, 1), 1}
	} else {
		box.color = color
	}
	box.name = get_name_from_id_string(id_string)
	box.rect = rect
	box.z_index = ui_state.z_index
	box.font_size = ui_state.font_size
	box.metadata = metadata
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
		box.hot = true
		signals.pressed = app.mouse.left_pressed
		signals.right_pressed = app.mouse.right_pressed
		if left_clicked_on_box(box, prev_signals) {
			if ui_state.last_active_box == box {
				time_diff_ms := (time.now()._nsec - ui_state.last_clicked_box_time._nsec) / 1000 / 1000
				if time_diff_ms <= 400 {
					signals.double_clicked = true
				}
			}
			printfln("clicked on {}", box.id_string)
			ui_state.active_box = box
			signals.clicked = true
			ui_state.last_clicked_box = box
			ui_state.last_clicked_box_time = time.now()
		}
		if right_clicked_on_box(box, prev_signals) {
			ui_state.right_clicked_on = box
			signals.right_clicked = true
			println("right button clicked on: ", box.id_string)
		}
		if app.mouse.wheel.y != 0 {
			signals.scrolled = true
		}
		if signals.pressed {
			signals.dragged_over = true
			if prev_signals.pressed {
				signals.dragging = true
			}
		}
	} else {
		box.hot = false
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
left_clicked_on_box :: proc(box: ^Box, prev_signals: Box_Signals) -> bool {
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
	return(
		prev_signals.pressed &&
		!app.mouse.left_pressed &&
		ui_state.active_box == nil &&
		.Clickable in box.flags \
	)
}

// Does expected checking, but also accounts for z-index stuff.
right_clicked_on_box :: proc(box: ^Box, prev_signals: Box_Signals) -> bool {
	if ui_state.active_box != nil {
		if box.z_index > ui_state.active_box.z_index {
			// might need to add more here
			if prev_signals.right_pressed && !app.mouse.right_pressed && .Clickable in box.flags {
				ui_state.active_box.active = false
				return true
			}
		}
		return false
	}
	return(
		prev_signals.right_pressed &&
		!app.mouse.right_pressed &&
		ui_state.active_box == nil &&
		.Clickable in box.flags \
	)
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
	px_amount := math.floor(get_pixel_change_amount(rect^, amount, "x"))
	rect.top_left.x = rect.top_left.x + px_amount
	return Rect {
		top_left = {parent_top_left_x, rect.top_left.y},
		bottom_right = {parent_top_left_x + px_amount, rect.bottom_right.y},
	}
}
cut_right :: proc(rect: ^Rect, amount: Size) -> Rect {
	parent_bottom_right_x: f32 = rect.bottom_right.x
	px_amount := math.floor(get_pixel_change_amount(rect^, amount, "x"))
	rect.bottom_right.x = rect.bottom_right.x - px_amount
	return Rect {
		top_left = {parent_bottom_right_x - px_amount, rect.top_left.y},
		bottom_right = {parent_bottom_right_x, rect.bottom_right.y},
	}
}
cut_top :: proc(rect: ^Rect, amount: Size) -> Rect {
	parent_top_left_y: f32 = rect.top_left.y
	px_amount := math.floor(get_pixel_change_amount(rect^, amount, "y"))
	rect.top_left.y = rect.top_left.y + px_amount
	return Rect{{rect.top_left.x, parent_top_left_y}, {rect.bottom_right.x, parent_top_left_y + px_amount}}
}
cut_bottom :: proc(rect: ^Rect, amount: Size) -> Rect {
	parent_bottom_right_y: f32 = rect.bottom_right.y
	px_amount := math.floor(get_pixel_change_amount(rect^, amount, "y"))
	rect.bottom_right.y = rect.bottom_right.y - px_amount
	return Rect {
		{rect.top_left.x, parent_bottom_right_y - px_amount},
		{rect.bottom_right.x, parent_bottom_right_y},
	}
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
	px_amount := math.floor(get_pixel_change_amount(rect, amount, "x"))
	return Rect {
		top_left = {parent_top_left_x, rect.top_left.y},
		bottom_right = {parent_top_left_x + px_amount, rect.bottom_right.y},
	}
}
get_right :: proc(rect: Rect, amount: Size) -> Rect {
	parent_bottom_right_x: f32 = rect.bottom_right.x
	px_amount := math.floor(get_pixel_change_amount(rect, amount, "x"))
	return Rect {
		top_left = {parent_bottom_right_x - px_amount, rect.top_left.y},
		bottom_right = {parent_bottom_right_x, rect.bottom_right.y},
	}
}
get_top :: proc(rect: Rect, amount: Size) -> Rect {
	parent_top_left_y: f32 = rect.top_left.y
	px_amount := math.floor(get_pixel_change_amount(rect, amount, "y"))
	return Rect{{rect.top_left.x, parent_top_left_y}, {rect.bottom_right.x, parent_top_left_y + px_amount}}
}
get_bottom :: proc(rect: Rect, amount: Size) -> Rect {
	parent_bottom_right_y: f32 = rect.bottom_right.y
	px_amount := math.floor(get_pixel_change_amount(rect, amount, "y"))
	return Rect {
		{rect.top_left.x, parent_bottom_right_y - px_amount},
		{rect.bottom_right.x, parent_bottom_right_y},
	}
}

// add_* lets you add to a rectangle, using same sizing semantics as when cutting.
add_left :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_pixel_change_amount(rect, amount, "x"))
	new_rect := rect
	new_rect.top_left.x = rect.top_left.x - px_amount
	return new_rect
}
add_right :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_pixel_change_amount(rect, amount, "x"))
	new_rect := rect
	new_rect.bottom_right.x = rect.bottom_right.x + px_amount
	return new_rect
}
add_top :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_pixel_change_amount(rect, amount, "y"))
	new_rect := rect
	new_rect.top_left.y = rect.top_left.y - px_amount
	return new_rect
}
add_bottom :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_pixel_change_amount(rect, amount, "y"))
	new_rect := rect
	new_rect.bottom_right.y = rect.bottom_right.y + px_amount
	return new_rect
}

// Let's you add pixels in a specific direction.
expand_x :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_pixel_change_amount(rect, amount, "x"))
	new_rect := rect
	new_rect.top_left.x = rect.top_left.x - px_amount
	new_rect.bottom_right.x = rect.bottom_right.x + px_amount
	return new_rect
}
expand_y :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_pixel_change_amount(rect, amount, "y"))
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
	px_amount := math.floor(get_pixel_change_amount(rect, amount, "x")) / 2
	new_rect := rect
	new_rect.top_left.x = rect.top_left.x + px_amount
	new_rect.bottom_right.x = rect.bottom_right.x - px_amount
	return new_rect
}
shrink_y :: proc(rect: Rect, amount: Size) -> Rect {
	px_amount := math.floor(get_pixel_change_amount(rect, amount, "y"))
	new_rect := rect
	new_rect.top_left.y = rect.top_left.y - px_amount
	new_rect.bottom_right.y = rect.bottom_right.y + px_amount
	return new_rect
}
shrink :: proc(rect: Rect, amount: Size) -> Rect {
	return shrink_x(shrink_y(rect, amount), amount)
}


// Let's you nudge rects by some amount in some direction.
Direction :: enum {
	up,
	right,
	down,
	left,
}

// Let's you 'nudge' a box slightly in some direction. Should never be used
// for large movements, that most likely indicates you have a layout issue.
nudge_rect :: proc(rect: ^Rect, amount: f32, direction: Direction) {
	switch direction {
	case .up:
		rect.top_left.y -= amount
		rect.bottom_right.y -= amount
	case .right:
		rect.top_left.x += amount
		rect.bottom_right.x += amount
	case .down:
		rect.top_left.y += amount
		rect.bottom_right.y += amount
	case .left:
		rect.top_left.x -= amount
		rect.bottom_right.x -= amount
	}
}
// Calulcates actual pixel amount based on abstract size.
get_pixel_change_amount :: proc(rect: Rect, amount: Size, direction: string) -> f32 {
	switch amount.kind {
	case .Percent:
		if direction == "x" {
			return rect_width(rect) * amount.value
		} else {
			return rect_height(rect) * amount.value
		}
	case .Pixels:
		return amount.value
	}
	panic("somethings gone wrong in trying to get shrink amount :(")
}

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
	append(&ui_state.color_stack, color)
	ui_state.override_color = true
}

pop_color :: proc() -> Color {
	if len(ui_state.color_stack) < 1 {
		panic("Tried to pop off empty color stack")
	}
	ui_state.override_color = false
	return pop(&ui_state.color_stack)
}

clear_color_stack :: proc() {
	clear_dynamic_array(&app.ui_state.color_stack)
}

top_color :: proc() -> (Color, bool) {
	n_colors := len(ui_state.color_stack)
	if n_colors < 1 do return {-1, -1, -1, -1}, false
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
	// printfln("trying to get id from id_string: '{}'", id_string)
	from := strings.index(id_string, "@")
	return id_string[from + 1:]
}

spacer :: proc(id_string: string, rect_cut: RectCut) -> ^Box {
	rect := cut_rect(top_rect(), rect_cut)
	s := box_from_cache({}, id_string, rect)
	append(&ui_state.temp_boxes, s)
	return s
}

// make_square_cutting_x :: proc(rect: ^Rect) {

// }
// make_square_cutting_y :: proc(rect: ^Rect) {

// }

// will shrink rect to make it a square, it will cut the minimum amount off
// the left AND right of the longer side.
rect_to_square :: proc(rect: Rect) -> Rect {
	rect := rect
	height := rect_height(rect)
	width := rect_width(rect)
	diff := width - height
	// width greater than height
	if diff > 0 {
		rect.top_left.x += diff / 2
		rect.bottom_right.x -= diff / 2
	} else { 	// width less than height => shrink height
		rect.top_left.y += diff / 2
		rect.bottom_right.y -= diff / 2
	}
	return rect
}

// move all boxes left so that they touch each other, optionally apply margin between
pack_to_left :: proc(rects: []^Rect, margin: f32 = 0) {
	for i := 0; i < len(rects) - 1; i += 1 {
		gap_to_right := rects[i + 1].top_left.x - rects[i].bottom_right.x
		rects[i + 1].top_left.x -= gap_to_right - margin
		rects[i + 1].bottom_right.x -= gap_to_right - margin
	}
}
pack_to_right :: proc(rects: []^Rect, margin: f32 = 0) {
	for i := len(rects) - 1; i >= 1; i -= 1 {
		gap_to_left := rects[i].top_left.x - rects[i - 1].bottom_right.x
		rects[i - 1].top_left.x += gap_to_left - margin
		rects[i - 1].bottom_right.x += gap_to_left - margin
	}
}

// Slices along x axis - like slicing vegetables. 
cut_rect_into_n_horizontally :: proc(
	rect: Rect,
	n: u32,
	allocator: mem.Allocator = context.temp_allocator,
) -> [dynamic]Rect {
	assert(n > 0)
	tl := rect.top_left
	br := rect.bottom_right
	piece_width := rect_width(rect) / f32(n)
	piece_height := rect_height(rect)
	bl := rect.top_left.xy + {0, piece_height}
	slices := make([dynamic]Rect, allocator = allocator)
	for i in 0 ..< n {
		new_rect := Rect{tl.xy + {(f32(i) * piece_width), 0}, bl.xy + {f32(i + 1) * piece_width, 0}}
		append(&slices, new_rect)
	}
	return slices
}

// Slices along y axis - like collapsing a tower. 
cut_rect_into_n_vertically :: proc(
	rect: Rect,
	n: u32,
	allocator: mem.Allocator = context.temp_allocator,
) -> [dynamic]Rect {
	tl := rect.top_left
	br := rect.bottom_right
	piece_width := rect_width(rect)
	piece_height := rect_height(rect) / f32(n)
	tr := tl.xy + {piece_width, 0}
	slices := make([dynamic]Rect, allocator = allocator)
	for i in 0 ..< n {
		new_rect := Rect{tl.xy + {0, f32(i) * piece_height}, tr.xy + {0, f32(i + 1) * piece_height}}
		append(&slices, new_rect)
	}
	return slices
}
