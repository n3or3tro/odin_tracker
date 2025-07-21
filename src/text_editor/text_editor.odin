package text_editor
// Basic text editing functionallity for a 1 dimensional line of text.
import "core:mem"
import "core:strings"


Edit_State :: struct {
	cursor_pos: u32,
	selecting:  bool,
	select_end: u32,
	data:       string,
}

create :: proc(state: ^Edit_State, allocator: mem.Allocator = context.allocator) {
	new_editor := new(Edit_State)
}

move_left :: proc(state: ^Edit_State) {
}

move_right :: proc(state: ^Edit_State) {
}

move_start :: proc(state: ^Edit_State) {
}

move_end :: proc(state: ^Edit_State) {
}

start_select :: proc(state: ^Edit_State) {
}

stop_select :: proc(state: ^Edit_State) {
}

insert_string :: proc(state: ^Edit_State) {
}

insert_rune :: proc(state: ^Edit_State, ch: rune) {
}

select_all :: proc(state: ^Edit_State) {
	state.cursor_pos = 0
	state.selecting = true
	state.select_end = len(data) - 1
}

delete_left :: proc(state: ^Edit_State) {

}

delete_right :: proc(state: ^Edit_State) {

}
