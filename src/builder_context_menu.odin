package main

Context_Menu_Signals :: struct {}

context_menu :: proc() -> Context_Menu_Signals {
	mouse_x := ui_state.mouse.pos.x
	mouse_y := ui_state.mouse.pos.y
	println(mouse_x, mouse_y)
	menu_top_left := [2]f32{f32(mouse_x), f32(mouse_y)}
	menu_bottom_right := [2]f32{f32(mouse_x) + 200, f32(mouse_y) + 500}

	// context.allocator = context.temp_allocator
	// container(aprintf("context-menu@lol"), Rect{menu_top_left, menu_bottom_right})

	return Context_Menu_Signals{}
}
