package ui_builder
import core "../ui_core"
Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32


// right now we take in an explicit rect_size, but in the future this will
// be determined by looking at the layout / app state.
button :: proc(ui_state: ^core.UI_State, text: string, size: [2]core.Size) -> core.Box_Signals {
	b := core.box_from_cache(
		{.Clickable, .Draw_Background, .Draw, .Draw_Text, .Hot_Animation},
		ui_state,
		text,
		size,
	)
	// add to list so we can render it later
	append(&ui_state.temp_boxes, b)
	return core.box_signals(ui_state^, b)
}
