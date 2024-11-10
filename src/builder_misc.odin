package main

// The id_strings are interesting here, not sure how much we need to care about them.
// On the other hand having them all with the same value might lead to issues.
// At the moment we skip the cache by using box_from_cache.
space :: proc(size: [2]Size, id_string: string) -> ^Box {
	return box_from_cache({}, id_string, size)
}

x_space :: proc(percent: f32, id_string: string) -> ^Box {
	return box_from_cache(
		{},
		id_string,
		{{kind = .Pecent_Of_Parent, value = percent}, {kind = .Pecent_Of_Parent, value = 0}},
	)
}

y_space :: proc(percent: f32, id_string: string) -> ^Box {
	return box_from_cache(
		{},
		id_string,
		{{kind = .Pecent_Of_Parent, value = 0}, {kind = .Pecent_Of_Parent, value = percent}},
	)
}

x_space_pixels :: proc(amount: f32, id_string: string) -> ^Box {
	return box_from_cache(
		{},
		id_string,
		{{kind = .Pixels, value = amount}, {kind = .Pixels, value = 0}},
	)
}

y_space_pixels :: proc(amount: f32, id_string: string) -> ^Box {
	return box_from_cache(
		{},
		id_string,
		{{kind = .Pixels, value = 0}, {kind = .Pixels, value = amount}},
	)
}
custom_space_x :: proc(percent: f32, id_string: string) -> ^Box {
	b := box_from_cache(
		{.No_Offset},
		id_string,
		{{kind = .Pecent_Of_Parent, value = percent}, {kind = .Pixels, value = 0}},
	)
	b.calc_rel_pos = {0, 0}
	return b
}
custom_space_y :: proc(percent: f32, id_string: string) -> ^Box {
	b := box_from_cache(
		{.No_Offset},
		id_string,
		{{kind = .Pecent_Of_Parent, value = 0}, {kind = .Pixels, value = percent}},
	)
	b.calc_rel_pos = {0, 0}
	return b
}
