// Misellaneous functions that are used in the main file. As the project grows, they may find a 
// logical home elswewhere.
package main
import sdl "vendor:sdl2"

Theme :: struct {
	main_color:   Vec3,
	second_color: Vec3,
	third_color:  Vec3,
	fourth_color: Vec3,
	fifth_color:  Vec3,
	sixth_color:  Vec3,
}

default_theme := Theme {
	Vec3{34.0, 23.0, 122.0},
	Vec3{96, 94, 161},
	Vec3{142, 163, 166},
	Vec3{230, 233, 17},
	Vec3{130, 233, 17},
	Vec3{30, 233, 17},
}

keep_aspect_ratio :: proc(window_width, window_height: i32) -> (i32, i32) {
	// height should be a ratio of with
	// return window_width, window_width * 10 / 16
	return window_height * 16 / 10, window_width
}

map_range :: proc(in_min, in_max, out_min, out_max, value: f32) -> f32 {
	return ((value - in_min) * (out_max - out_min) / (in_max - in_min)) + out_min
}
calc_slider_volume :: proc(in_min, in_max, out_min, out_max, value: f32) -> f32 {
	mapped_value := map_range(in_min, in_max, out_min, out_max, value)
	return abs(-1 * (1 - mapped_value))
}

change_cursor :: proc(type: sdl.SystemCursor) {
	hand_cursor := sdl.CreateSystemCursor(type)
	if hand_cursor == nil {
		panic("couldnt create cursor")
	}
	sdl.SetCursor(hand_cursor)
}
rect_height :: proc(rect: Rect) -> f32 {
	return rect.bottom_right.y - rect.top_left.y
}
rect_width :: proc(rect: Rect) -> f32 {
	return rect.bottom_right.x - rect.top_left.x
}
