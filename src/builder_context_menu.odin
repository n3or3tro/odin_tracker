package main

Context_Menu_Signals :: struct {
}

context_menu :: proc() -> Context_Menu_Signals {
	mouse_x := app.mouse.pos.x
	mouse_y := app.mouse.pos.y
	println(mouse_x, mouse_y)
	menu_top_left := [2]f32{f32(mouse_x), f32(mouse_y)}
	menu_bottom_right := [2]f32{f32(mouse_x) + 200, f32(mouse_y) + 500}
	return Context_Menu_Signals{}
}
