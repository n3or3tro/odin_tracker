// Code associated with layout algorithm for the UI.

package ui_core
import "base:intrinsics"
import "core:fmt"
import "core:math"
import random "core:math/rand"
Layout_Stack :: [dynamic]^Box
max :: proc(a, b: $T) -> T where intrinsics.type_is_numeric(T) {
	return a if a >= b else b
}

layout_push_parent :: proc(layout_stack: ^Layout_Stack, box: ^Box) {
	val, err := append_elem(layout_stack, box)
	if err != .None {
		println(err)
		panic("^^^")
	}
}

layout_pop_parent :: proc(layout_stack: ^Layout_Stack) -> ^Box {
	if len(layout_stack) > 0 {
		return pop(layout_stack)
	} else {
		panic("layout_pop_parent: layout_stack is empty")
	}
	return nil
}


// Doesn't account for padding or anything like that.
calculate_text_size :: proc(char_map: map[rune]Character, text: string) -> Vec2 {
	width, height: f32 = 0, 0
	for c in text {
		character := char_map[c]
		width += character.size[0]
		height = max(height, character.size[1])
	}
	return Vec2{width, height}
}
get_text_from_idstring :: proc(id_string: string) -> string {
	return id_string
}

calc_standalone_sizes :: proc(ui_state: UI_State, root: ^Box, axis: Axis) {
	#partial switch root.pref_size[axis].kind {
	case .Pixels:
		// The way our data is setup, root.rect should already be set here
		root.calc_size[axis] = math.floor(root.pref_size[axis].value)
	case .Text_Content:
		switch axis {
		// At the moment the switch is pointless, but most likely x and y will
		// be handled differently.
		case .X:
			root.calc_size[axis] = calculate_text_size(ui_state.char_map, root.id_string).x
			// Should add code for padding here.
			root.calc_size[axis] = math.ceil(root.calc_size[axis])
		case .Y:
			root.calc_size[axis] = calculate_text_size(ui_state.char_map, root.id_string).y
			// Should add code for padding here.
			root.calc_size[axis] = math.floor(root.calc_size[axis])
		}
	}
	for child := root.first; child != nil; child = child.next {
		calc_standalone_sizes(ui_state, child, axis)
	}
}

calc_upwards_dependant_sizes :: proc(ui_state: UI_State, root: ^Box, axis: Axis) {
	#partial switch root.pref_size[axis].kind {
	case .Pecent_Of_Parent:
		ancestor: ^Box
		for node := root.parent; node != nil; node = node.parent {
			if node.pref_size[axis].kind != .Children_Sum {
				ancestor = node
				break
			}
		}
		if ancestor != nil {
			root.calc_size[axis] = math.floor(
				ancestor.calc_size[axis] * root.pref_size[axis].value,
			)
		}
	}
	for child := root.first; child != nil; child = child.next {
		calc_upwards_dependant_sizes(ui_state, child, axis)
	}
}

calc_downwards_dependant_sizes :: proc(ui_state: UI_State, root: ^Box, axis: Axis) {
	// Unlike other layout functions, we recurse first as we may depend on children
	// that have the same downward dependance property.
	for child := root.first; child != nil; child = child.next {
		calc_downwards_dependant_sizes(ui_state, child, axis)
	}
	#partial switch root.pref_size[axis].kind {
	case .Children_Sum:
		val: f32 = 0
		if axis == root.child_layout_axis {
			for child := root.first; child != nil; child = child.next {
				val += child.calc_size[axis]
			}
		} else {
			for child := root.first; child != nil; child = child.next {
				val = max(val, child.calc_size[axis])
			}
		}
		root.calc_size[axis] = math.floor(val)
	}
}

solve_size_violations :: proc(ui_state: UI_State, root: ^Box, axis: Axis) {
	// we're not doing this yet xD
}

calc_positions :: proc(ui_state: UI_State, root: ^Box, axis: Axis) {
	// println("calculating position of: ", root.id_string)
	if axis == root.child_layout_axis {
		tmp: f32 = 0
		for child := root.first; child != nil; child = child.next {
			if .No_Offset in child.flags {
				// will be set manually in builder code.
			} else {
				// child.calc_rel_pos[axis] += tmp
				child.calc_rel_pos[axis] = tmp
			}
			tmp += child.calc_size[axis]
		}
	}
	for child := root.first; child != nil; child = child.next {
		// last_rel_rect := child.rel_rect
		child.rel_rect[0][axis] = child.calc_rel_pos[axis]
		child.rel_rect[1][axis] = child.rel_rect.x[axis] + child.calc_size[axis]
		child.rect[0][axis] = root.rect[0][axis] + child.rel_rect[0][axis]
		child.rect[1][axis] = child.rect[0][axis] + child.calc_size[axis]
		if !(.Floating_X in child.flags) {
			child.rect[0][axis] = math.floor(child.rect[0][axis])
			child.rect[1][axis] = math.floor(child.rect[1][axis])
		}
	}
	for child := root.first; child != nil; child = child.next {
		calc_positions(ui_state, child, axis)
	}
}

layout_from_root :: proc(ui_state: UI_State, root: ^Box, axis: Axis) {
	calc_standalone_sizes(ui_state, root, axis)
	calc_upwards_dependant_sizes(ui_state, root, axis)
	calc_downwards_dependant_sizes(ui_state, root, axis)
	calc_positions(ui_state, root, axis)
	// enforce_layout_constraints(ui_state, root)
	// calc_layout_positions(ui_state, root)
}
