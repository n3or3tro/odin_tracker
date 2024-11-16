// Misellaneous functions that are used in the main file. As the project grows, they may find a 
// logical home elswewhere.
package main

map_range :: proc(in_min, in_max, out_min, out_max, value: f32) -> f32 {
	return ((value - in_min) * (out_max - out_min) / (in_max - in_min)) + out_min
}
calc_slider_volume :: proc(in_min, in_max, out_min, out_max, value: f32) -> f32 {
	mapped_value := map_range(in_min, in_max, out_min, out_max, value)
	return abs(-1 * (1 - mapped_value))
}
