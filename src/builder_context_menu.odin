package main
import str "core:strings"

Context_Menu_Signals :: struct {
	b1: Box_Signals,
	b2: Box_Signals,
	b3: Box_Signals,
	b4: Box_Signals,
}

// context_menu :: proc() -> Context_Menu_Signals {
context_menu :: proc() {
	ui_state.z_index = 10
	defer ui_state.z_index = 0
	mouse_x := ui_state.context_menu_pos.x
	mouse_y := ui_state.context_menu_pos.y
	id: string
	if ui_state.right_clicked_on == nil {
		item_clicked_on_name := "none"
		printfln("context menu item is: {}", item_clicked_on_name)
	} else {
		id = ui_state.right_clicked_on.id_string
	}

	button_height: f32 = 40
	button_width: f32 = 200

	first_button_tl := Vec2{mouse_x, mouse_y}
	first_button_br := Vec2{mouse_x + button_width, mouse_y + button_height}

	if str.contains(id, "track") {
		delete_btn := text_button("delete@context-menu-delete-track", Rect{first_button_tl, first_button_br})
		if delete_btn.clicked {
			track_num := get_track_num_from_track_id(id)
			app.tracks[track_num] = false
			printfln("deleting track {}", track_num)
		}
	}
}
