package main
import str "core:strings"


Menu_Item :: struct {
	label:     string,
	action_id: string,
	submenu:   ^Menu,
	action:    proc(),
}

Menu :: struct {
	items: [dynamic]Menu_Item,
}

// Represents a single, currently visible menu panel.
Active_Menu :: struct {
	position:    Vec2, // Top-left screen position where the menu should be drawn.
	menu_data:   ^Menu, // The menu to display.
	parent_rect: Rect, // The rect of the menu item that opened this menu (used for positioning).
}

// The complete state for the entire menu system.
Menu_System_State :: struct {
	is_active:  bool,
	// A stack of currently open menus and submenus.
	menu_stack: [dynamic]Active_Menu,
}

ctx_menu_height :: 24.0
ctx_menu_width :: 200.0

context_menu :: proc() {
	ui_state.z_index = 20
	defer ui_state.z_index = 0

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

// Draws the entire menu stack and returns an action_id if an item is clicked.
context_menu :: proc(menu_system: ^Menu_System_State) -> (action_id: string, ok: bool) {
	if !menu_system.is_active {
		return "", false
	}

	// --- Dismissal Logic ---
	// Close the menu if a click happened and it wasn't on a menu item.
	if app.mouse.clicked {
		is_on_menu := false
		if ui_state.last_active_box != nil && strings.contains(ui_state.last_active_box.id_string, "menu-item") {
			is_on_menu = true
		}
		if !is_on_menu {
			menu_system.is_active = false
			return "", false
		}
	}


	// --- Drawing and Interaction Logic ---
	ui_state.z_index = 8 // Ensure menus draw on top of other UI.

	// Keep track of which items are hovered this frame.
	any_item_hovered := false

	// Iterate over the stack of open menus (e.g., main menu, then first submenu, etc.).
	for i in 0 ..< len(menu_system.menu_stack) {
		active_menu := &menu_system.menu_stack[i]

		// Draw each menu item as a button.
		item_y_offset: f32 = 0
		for item_idx in 0 ..< len(active_menu.menu_data.items) {
			item := &active_menu.menu_data.items[item_idx]

			// Create the button for the menu item.
			item_rect := Rect {
				top_left     = active_menu.position + {0, item_y_offset},
				bottom_right = active_menu.position + {ctx_menu_width, item_y_offset + ctx_menu_height},
			}
			// The unique ID includes the menu level and item index to be safe.
			item_id := tprintf("%s@menu-item-%d-%d", item.label, i, item_idx)
			item_button := text_button(item_id, item_rect)

			item_y_offset += rect_height(item_rect)

			if item_button.hovering {
				any_item_hovered = true

				// If this item has a submenu, we need to manage the stack.
				if item.submenu != nil {
					// A new submenu needs to be opened. First, pop any deeper submenus off the stack.
					for len(menu_system.menu_stack) > i + 1 {
						pop(&menu_system.menu_stack)
					}
					// Then, if the new submenu isn't already open, push it onto the stack.
					if len(menu_system.menu_stack) <= i + 1 {
						new_submenu_pos := item_rect.top_left + {rect_width(item_rect), 0}
						new_active_menu := Active_Menu {
							menu_data   = item.submenu,
							position    = new_submenu_pos,
							parent_rect = item_rect,
						}
						append(&menu_system.menu_stack, new_active_menu)
					}
				} else {
					// This item has NO submenu, so close any submenus that are currently open from this level.
					for len(menu_system.menu_stack) > i + 1 {
						pop(&menu_system.menu_stack)
					}
				}
			}

			// If an item with an action is clicked, return the action and close the menu system.
			if item_button.clicked {
				if item.action_id != "" {
					menu_system.is_active = false
					return item.action_id, true
				}
			}
		}
	}

	ui_state.z_index = 0 // Reset z-index.
	return "", false
}

// // context_menu :: proc() -> Context_Menu_Signals {
// context_menu :: proc() {
// 	ui_state.z_index = 8
// 	defer ui_state.z_index = 0
// 	mouse_x := ui_state.context_menu.pos.x
// 	mouse_y := ui_state.context_menu.pos.y

// 	button_height: f32 = 20
// 	button_width: f32 = 200

// 	first_button_tl := Vec2{mouse_x, mouse_y}
// 	first_button_br := Vec2{mouse_x + button_width, mouse_y + button_height}
// 	if ui_state.right_clicked_on == nil {
// 		return
// 	}
// 	switch metadata in ui_state.right_clicked_on.metadata {
// 	case Step_Metadata:
// 		step_context_menu(metadata)
// 	case Sampler_Metadata:
// 	case Track_Control_Metadata:
// 	case Context_Menu_Metadata:
// 	case No_Metadata:
// 	}
// }


step_context_menu :: proc(metadata: Step_Metadata) {
	mouse_x := ui_state.context_menu.pos.x
	mouse_y := ui_state.context_menu.pos.y
	menu_end := mouse_x + ctx_menu_width
	delete_btn_rect := Rect{{mouse_x, mouse_y}, {menu_end, mouse_y + ctx_menu_height}}
	delete_btn := text_button("Delete@context-menu-delete-track", delete_btn_rect, metadata = Context_Menu_Metadata{})

	if delete_btn.clicked {
		track_num := metadata.track_num
		app.tracks[track_num] = false
	}

	prev := delete_btn_rect
	fill_menu_rect := Rect{{mouse_x, prev.bottom_right.y}, {menu_end, prev.bottom_right.y + ctx_menu_height}}
	fill_menu := text_button("Set notes@context-menu-set-menu", fill_menu_rect, metadata = Context_Menu_Metadata{})

	// Handle 'set' submenu creation and hide/show
	is_submenu_hovered := false
	if ui_state.context_menu.show_fill_note_menu || ui_state.context_menu.show_add_step_menu {
		is_submenu_hovered = edit_steps_submenu(metadata, fill_menu_rect, fill = true)
	}
	if fill_menu.hovering || is_submenu_hovered {
		ui_state.context_menu.show_fill_note_menu = true
	} else {
		ui_state.context_menu.show_fill_note_menu = false
	}

	prev = fill_menu_rect
	remove_menu_rect := Rect{{mouse_x, prev.bottom_right.y}, {menu_end, prev.bottom_right.y + ctx_menu_height}}
	remove_menu := text_button(
		"Unset notes@context-menu-remove-menu",
		remove_menu_rect,
		metadata = Context_Menu_Metadata{},
	)

	prev = remove_menu_rect
	add_step_rect := Rect{{mouse_x, prev.bottom_right.y}, {menu_end, prev.bottom_right.y + ctx_menu_height}}
	add_step := text_button("Add steps@context-menu-add-step-menu", add_step_rect, metadata = Context_Menu_Metadata{})

	// Handle 'set' submenu creation and hide/show
	is_submenu_hovered = false
	if ui_state.context_menu.show_remove_note_menu {
		is_submenu_hovered = edit_steps_submenu(metadata, remove_menu_rect, fill = false)
	}
	if ui_state.context_menu.show_add_step_menu {
		is_submenu_hovered = add_remove_steps_submenu(metadata, remove_menu_rect, add = true)
	}
	if remove_menu.hovering || is_submenu_hovered {
		ui_state.context_menu.show_remove_note_menu = true
	} else {
		ui_state.context_menu.show_remove_note_menu = false
	}
	if delete_btn.clicked {
		ui_state.context_menu.active = false
	}
}

edit_steps_submenu :: proc(metadata: Step_Metadata, parent_rect: Rect, fill: bool = true) -> (hovering: bool) {
	track_num := metadata.track_num
	menu_x := parent_rect.bottom_right.x - 3
	menu_end := menu_x + ctx_menu_width
	menu_y := parent_rect.top_left.y
	menu_start_tl := Vec2{menu_x, menu_y}

	every_step_rect := Rect{menu_start_tl, menu_start_tl + {ctx_menu_width, ctx_menu_height}}
	every_step := text_button("Every step@context-menu-set-every", every_step_rect, metadata = Context_Menu_Metadata{})
	track := app.audio_state.tracks[track_num]
	if every_step.clicked {
		for i in 0 ..< len(track.selected_steps) {
			if fill {
				track.selected_steps[i] = true
				enable_step(
					ui_state.box_cache[create_substep_input_id(u32(i), track_num, app.samplers[track_num].mode == .slice ? .Pitch_Slice : .Pitch_Note)],
				)
			} else {
				track.selected_steps[i] = false
			}
		}
	}

	prev := every_step_rect
	second_step_rect := Rect{{menu_x, prev.bottom_right.y}, {menu_end, prev.bottom_right.y + ctx_menu_height}}
	second_step := text_button(
		"Every second@context-menu-set-second",
		second_step_rect,
		metadata = Context_Menu_Metadata{},
	)
	if second_step.clicked {
		for i: u32 = 0; i < track.n_steps; i += 2 {
			if fill {
				track.selected_steps[i] = true
			} else {
				track.selected_steps[i] = false
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
		for i: u32 = 0; i < track.n_steps; i += 3 {
			if fill {
				track.selected_steps[i] = true
			} else {
				track.selected_steps[i] = false
			}
		}
	}

	prev = third_step_rect
	fourth_step_rect := Rect{{menu_x, prev.bottom_right.y}, {menu_end, prev.bottom_right.y + ctx_menu_height}}
	fourth_step := text_button(
		"Every fourth@context-menu-set-fourth",
		fourth_step_rect,
		metadata = Context_Menu_Metadata{},
	)
	if fourth_step.clicked {
		for i: u32 = 0; i < track.n_steps; i += 4 {
			if fill {
				track.selected_steps[i] = true
			} else {
				track.selected_steps[i] = false
			}
		}
	}
	if every_step.clicked || second_step.clicked || third_step.clicked || fourth_step.clicked {
		ui_state.context_menu.active = false
	}
	return every_step.hovering || second_step.hovering || third_step.hovering || fourth_step.hovering
}

add_remove_steps_submenu :: proc(metadata: Step_Metadata, parent_rect: Rect, add: bool = true) -> (hovering: bool) {
	actually_add_remove_steps_submenu :: proc(
		metadata: Step_Metadata,
		parent_rect: Rect,
		add: bool = true,
		ratio: bool = false,
	) -> (
		hovering: bool,
	) {

		track_num := metadata.track_num
		track := app.audio_state.tracks[track_num]
		menu_x := parent_rect.bottom_right.x - 3
		menu_end := menu_x + ctx_menu_width
		menu_y := parent_rect.top_left.y
		menu_start_tl := Vec2{menu_x, menu_y}
		// ratio_rect := Rect{menu_start_tl, menu_start_tl + {ctx_menu_width, ctx_menu_height}}
		// ratio_btn := text_button("Ratio@context-menu-add-ratio", ratio_rect, metadata = Context_Menu_Metadata{})

		// prev := ratio_rect
		// absolute_rect := Rect{{menu_x, prev.bottom_right.y}, {menu_end, prev.bottom_right.y + ctx_menu_height}}
		// absolute_btn := text_button(
		// 	"Absolute@context-menu-add-absolute",
		// 	absolute_rect,
		// 	metadata = Context_Menu_Metadata{},
		// )

		return true
	}

	menu_x := parent_rect.bottom_right.x - 3
	menu_end := menu_x + ctx_menu_width
	menu_y := parent_rect.top_left.y
	menu_start_tl := Vec2{menu_x, menu_y}

	ratio_rect := Rect{menu_start_tl, menu_start_tl + {ctx_menu_width, ctx_menu_height}}
	ratio_btn := text_button("Ratio@context-menu-add-ratio", ratio_rect, metadata = Context_Menu_Metadata{})

	prev := ratio_rect
	absolute_rect := Rect{{menu_x, prev.bottom_right.y}, {menu_end, prev.bottom_right.y + ctx_menu_height}}
	absolute_btn := text_button(
		"Absolute@context-menu-add-absolute",
		absolute_rect,
		metadata = Context_Menu_Metadata{},
	)
	if absolute_btn.hovering {
		actually_add_remove_steps_submenu(metadata, absolute_rect, add, ratio = false)
	} else if ratio_btn.hovering {
		actually_add_remove_steps_submenu(metadata, absolute_rect, add, ratio = true)
	}
	// return every_step.hovering || second_step.hovering || third_step.hovering || fourth_step.hovering
	return ratio_btn.hovering || absolute_btn.hovering
}
