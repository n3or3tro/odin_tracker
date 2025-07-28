package main
import str "core:strings"

Context_Menu_Signals :: struct {
	b1: Box_Signals,
	b2: Box_Signals,
	b3: Box_Signals,
	b4: Box_Signals,
}

ctx_menu_height: f32 = 24
ctx_menu_width: f32 = 200

step_context_menu :: proc(metadata: Step_Metadata) {
	mouse_x := ui_state.context_menu.pos.x
	mouse_y := ui_state.context_menu.pos.y
	menu_end := mouse_x + ctx_menu_width
	delete_btn_rect := Rect{{mouse_x, mouse_y}, {menu_end, mouse_y + ctx_menu_height}}
	delete_btn := text_button(
		"Delete@context-menu-delete-track",
		delete_btn_rect,
		metadata = Context_Menu_Metadata{},
	)

	if delete_btn.clicked {
		track_num := metadata.track_num
		app.tracks[track_num] = false
	}

	prev := delete_btn_rect
	fill_menu_rect := Rect{{mouse_x, prev.bottom_right.y}, {menu_end, prev.bottom_right.y + ctx_menu_height}}
	fill_menu := text_button("Set@context-menu-set-menu", fill_menu_rect, metadata = Context_Menu_Metadata{})

	// Handle 'set' submenu creation and hide/show
	is_submenu_hovered := false
	if ui_state.context_menu.show_fill_menu {
		is_submenu_hovered = edit_steps_submenu(metadata, fill_menu_rect, fill = true)
	}
	if fill_menu.hovering || is_submenu_hovered {
		ui_state.context_menu.show_fill_menu = true
	} else {
		ui_state.context_menu.show_fill_menu = false
	}

	prev = fill_menu_rect
	remove_menu_rect := Rect {
		{mouse_x, prev.bottom_right.y},
		{menu_end, prev.bottom_right.y + ctx_menu_height},
	}
	remove_menu := text_button(
		"Remove@context-menu-remove-menu",
		remove_menu_rect,
		metadata = Context_Menu_Metadata{},
	)

	// Handle 'set' submenu creation and hide/show
	is_submenu_hovered = false
	if ui_state.context_menu.show_remove_menu {
		is_submenu_hovered = edit_steps_submenu(metadata, remove_menu_rect, fill = false)
	}
	if remove_menu.hovering || is_submenu_hovered {
		ui_state.context_menu.show_remove_menu = true
	} else {
		ui_state.context_menu.show_remove_menu = false
	}
	if delete_btn.clicked {
		ui_state.context_menu.active = false
	}
}

edit_steps_submenu :: proc(
	metadata: Step_Metadata,
	parent_rect: Rect,
	fill: bool = true,
) -> (
	hovering: bool,
) {
	track_num := metadata.track_num
	menu_x := parent_rect.bottom_right.x - 3
	menu_end := menu_x + ctx_menu_width
	menu_y := parent_rect.top_left.y
	menu_start_tl := Vec2{menu_x, menu_y}

	every_step_rect := Rect{menu_start_tl, menu_start_tl + {ctx_menu_width, ctx_menu_height}}
	every_step := text_button(
		"Every step@context-menu-set-every",
		every_step_rect,
		metadata = Context_Menu_Metadata{},
	)
	if every_step.clicked {
		for i in 0 ..< len(ui_state.selected_steps[track_num]) {
			if fill {
				ui_state.selected_steps[track_num][i] = true
				enable_step(
					ui_state.box_cache[create_substep_input_id(u32(i), track_num, app.samplers[track_num].mode == .slice ? .Pitch_Slice : .Pitch_Note)],
				)
			} else {
				ui_state.selected_steps[track_num][i] = false
			}
		}
	}

	prev := every_step_rect
	second_step_rect := Rect {
		{menu_x, prev.bottom_right.y},
		{menu_end, prev.bottom_right.y + ctx_menu_height},
	}
	second_step := text_button(
		"Every second@context-menu-set-second",
		second_step_rect,
		metadata = Context_Menu_Metadata{},
	)
	if second_step.clicked {
		for i := 0; i < len(ui_state.selected_steps[track_num]); i += 2 {
			if fill {
				ui_state.selected_steps[track_num][i] = true
			} else {
				ui_state.selected_steps[track_num][i] = false
			}
		}
	}

	prev = second_step_rect
	third_step_rect := Rect{{menu_x, prev.bottom_right.y}, {menu_end, prev.bottom_right.y + ctx_menu_height}}
	third_step := text_button(
		"Every third@context-menu-set-third",
		third_step_rect,
		metadata = Context_Menu_Metadata{},
	)
	if third_step.clicked {
		for i := 0; i < len(ui_state.selected_steps[track_num]); i += 3 {
			if fill {
				ui_state.selected_steps[track_num][i] = true
			} else {
				ui_state.selected_steps[track_num][i] = false
			}
		}
	}

	prev = third_step_rect
	fourth_step_rect := Rect {
		{menu_x, prev.bottom_right.y},
		{menu_end, prev.bottom_right.y + ctx_menu_height},
	}
	fourth_step := text_button(
		"Every fourth@context-menu-set-fourth",
		fourth_step_rect,
		metadata = Context_Menu_Metadata{},
	)
	if fourth_step.clicked {
		for i := 0; i < len(ui_state.selected_steps[track_num]); i += 4 {
			if fill {
				ui_state.selected_steps[track_num][i] = true
			} else {
				ui_state.selected_steps[track_num][i] = false
			}
		}
	}
	if every_step.clicked || second_step.clicked || third_step.clicked || fourth_step.clicked {
		ui_state.context_menu.active = false
	}
	return every_step.hovering || second_step.hovering || third_step.hovering || fourth_step.hovering
}

// context_menu :: proc() -> Context_Menu_Signals {
context_menu :: proc() {
	ui_state.z_index = 8
	defer ui_state.z_index = 0
	mouse_x := ui_state.context_menu.pos.x
	mouse_y := ui_state.context_menu.pos.y

	button_height: f32 = 20
	button_width: f32 = 200

	first_button_tl := Vec2{mouse_x, mouse_y}
	first_button_br := Vec2{mouse_x + button_width, mouse_y + button_height}
	if ui_state.right_clicked_on == nil {
		return
	}
	switch metadata in ui_state.right_clicked_on.metadata {
	case Step_Metadata:
		step_context_menu(metadata)
	case Sampler_Metadata:
	case Track_Control_Metadata:
	case Context_Menu_Metadata:
	case No_Metadata:
	}
}
