package main

Context_Menu_Signals :: struct {
	b1: Box_Signals,
	b2: Box_Signals,
	b3: Box_Signals,
	b4: Box_Signals,
}

context_menu :: proc() -> Context_Menu_Signals {
	ui_state.z_index = 5
	defer ui_state.z_index = 0
	mouse_x := ui_state.context_menu_pos.x
	mouse_y := ui_state.context_menu_pos.y
	// if ui_state.right_clicked_on == nil {
	// 	item_clicked_on_name := "none"
	// 	printfln("context menu item is: {}", item_clicked_on_name)
	// } else {
	// 	item_clicked_on_name := ui_state.right_clicked_on.id_string
	// 	printfln("context menu item is: {}", item_clicked_on_name)
	// }

	button_height: f32 = 70
	button_width: f32 = 300
	text_container(
		tprintf("heading :)@context_menu"),
		Rect{top_left = {mouse_x, mouse_y}, bottom_right = {mouse_x, mouse_y + button_height}},
	)
	first_button_tl := Vec2{mouse_x, mouse_y + button_height}
	first_button_br := Vec2{mouse_x + button_width, mouse_y + button_height * 2}
	b1 := text_button("context1@context_menu", Rect{first_button_tl, first_button_br})
	b2 := text_button(
		"context2@context_menu",
		Rect{top_left = b1.box.rect.top_left + Vec2{0, button_height}, bottom_right = b1.box.rect.bottom_right + [2]f32{0, button_height}},
	)
	b3 := text_button(
		"context3@context_menu",
		Rect{top_left = b2.box.rect.top_left + Vec2{0, button_height}, bottom_right = b2.box.rect.bottom_right + [2]f32{0, button_height}},
	)

	b4 := text_button(
		"context4@context_menu",
		Rect{top_left = b3.box.rect.top_left + Vec2{0, button_height}, bottom_right = b3.box.rect.bottom_right + [2]f32{0, button_height}},
	)
	if b1.clicked {
		println("b1 clicked")
	}
	if b2.clicked {
		println("b2 clicked")
	}
	if b3.clicked {
		println("b3 clicked")
	}
	if b4.clicked {
		println("b4 clicked")
	}
	return Context_Menu_Signals{b1, b2, b3, b4}
}
