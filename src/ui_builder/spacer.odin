package ui_builder
import core "../ui_core"

// The id_strings are interesting here, not sure how much we need to care about them.
// On the other hand having them all with the same value might lead to issues.
// At the moment we skip the cache by using box_from_cache.
space :: proc(ui_state: ^core.UI_State, size: [2]core.Size, id_string: string) -> ^core.Box {
	return core.box_from_cache({}, ui_state, id_string, size)
}

x_space :: proc(ui_state: ^core.UI_State, percent: f32, id_string: string) -> ^core.Box {
	return core.box_from_cache(
		{},
		ui_state,
		id_string,
		{{kind = .Pecent_Of_Parent, value = percent}, {kind = .Pecent_Of_Parent, value = 0}},
	)
}

y_space :: proc(ui_state: ^core.UI_State, percent: f32, id_string: string) -> ^core.Box {
	return core.box_from_cache(
		{},
		ui_state,
		id_string,
		{{kind = .Pecent_Of_Parent, value = 0}, {kind = .Pecent_Of_Parent, value = percent}},
	)
}

x_space_pixels :: proc(ui_state: ^core.UI_State, amount: f32, id_string: string) -> ^core.Box {
	return core.box_from_cache(
		{},
		ui_state,
		id_string,
		{{kind = .Pixels, value = amount}, {kind = .Pixels, value = 0}},
	)
}

y_space_pixels :: proc(ui_state: ^core.UI_State, amount: f32, id_string: string) -> ^core.Box {
	return core.box_from_cache(
		{},
		ui_state,
		id_string,
		{{kind = .Pixels, value = 0}, {kind = .Pixels, value = amount}},
	)
}
