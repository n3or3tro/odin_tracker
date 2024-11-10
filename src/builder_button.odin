package main
Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32


// right now we take in an explicit rect_size, but in the future this will
// be determined by looking at the layout / app state.
button :: proc(text: string, size: [2]Size) -> Box_Signals {
	b := box_from_cache(
		{.Clickable, .Draw_Background, .Draw, .Draw_Text, .Hot_Animation},
		text,
		size,
	)
	// add to list so we can render it later
	append(&ui_state.temp_boxes, b)
	// draw_text("button1", &text_vbuffer, &text_vabuffer, char_map, {cast(u32)wx, cast(u32)wy})
	return box_signals(b)
}
