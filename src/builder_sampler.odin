package main
// import sa "core:container/small_array"
import "core:mem"
import "core:slice"
import "core:sort"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"
// import "core"

Sampler_Slice :: struct {
	// How far along into the sound is this.
	how_far: f32,
	// Which slice is this. NOT the same as it's order along the x-axis.
	// This is included because I was getting weird issues upon re-ordering the existing
	// slices in sampler.slices.
	which:   u32,
}
Sampler_State :: struct {
	n_slices:         u32,
	mode:             enum {
		slice,
		warp,
		one_shot,
	},
	// Store how far along the length of the container the marker goes: [0-1].
	slices:           [128]Sampler_Slice,
	// How zoomed in the view of the wav data is.
	zoom_amount:      f32,
	// Where the zoom occurs 'around'. This changes as you move the mouse.
	// Doesn't change when you're zooming as it's relevant to the rect, not the wave.
	zoom_point:       f32,
	// To help avoid double actions on 'clicked' when dragging a slice.
	dragging_a_slice: bool,
	// Identify which slice is being dragged. Had issues with mouse going ahead of dragged box,
	// so trying to implement 'sticky stateful' dragging.
	dragged_slice:    u32,
}

Sampler_Signals :: struct {
	container_signals: Draggable_Container_Signals,
}

// takes in the container that the controls will be drawn inside.
sampler_left_controls :: proc(rect: ^Rect) {
	old_font_size := ui_state.font_size
	defer ui_state.font_size = old_font_size
	ui_state.font_size = .m
	track_num := get_active_track()
	top_left_info_rect := cut_rect(rect, {{.Percent, 0.1}, .Top})
	rects := cut_rect_into_n_vertically(rect^, 3)

	one_shot_rect := rects[0]
	warp_button_rect := rects[1]
	slice_button_rect := rects[2]

	one_shot_button := text_button("one shot@left-controls-one-shot", one_shot_rect)
	warp_button := text_button("warp whole sample@left-controls-warp", warp_button_rect)
	slice_button := text_button("slice up sample@left-controls-slice", slice_button_rect)

	if warp_button.clicked {
		app.samplers[track_num].mode = .warp
	} else if slice_button.clicked {
		app.samplers[track_num].mode = .slice
	} else if one_shot_button.clicked {
		app.samplers[track_num].mode = .one_shot
	}

	// Add info about sampler state on top left
	switch app.samplers[track_num].mode {
	case .one_shot:
		text_container("one shot mode@sampler-info-one-shot", top_left_info_rect)
	case .warp:
		text_container("warp mode@sampler-info-warp", top_left_info_rect)
	case .slice:
		text_container("slice mode@sampler-info-slice", top_left_info_rect)
	}
}

sampler_bottom_controls :: proc(rect: ^Rect, track_num: u32) {
	// Create ADSR controls
	adsr_rect := cut_left(rect, {.Percent, 0.3})
	rects := cut_rect_into_n_horizontally(adsr_rect, 4)

	attack_rect := rect_to_square(rects[0])
	decay_rect := rect_to_square(rects[1])
	sustain_rect := rect_to_square(rects[2])
	release_rect := rect_to_square(rects[3])

	pack_to_left({&attack_rect, &decay_rect, &sustain_rect, &release_rect}, margin = 15)
	ui_state.font_size = .xs
	knob_metadata := Sampler_Metadata{track_num, .ADSR_Knob, {}}
	attack_knob := knob(tprintf("attack@sampler-{}-attack-knob", track_num), &attack_rect, knob_metadata)
	decay_knob := knob(tprintf("decay@sampler-{}-decay-knob", track_num), &decay_rect, knob_metadata)
	sustain_knob := knob(tprintf("sustain@sampler-{}-sustain-knob", track_num), &sustain_rect, knob_metadata)
	release_knob := knob(tprintf("release@sampler-{}-release-knob", track_num), &release_rect, knob_metadata)
	ui_state.font_size = .l

	line(
		tprintf("line@sampler-{}-adsr_margin_line", track_num),
		{
			{adsr_rect.bottom_right.x, adsr_rect.top_left.y},
			{adsr_rect.bottom_right.x + 1, adsr_rect.bottom_right.y},
		},
	)

	remaining_rects := cut_rect_into_n_horizontally(rect^, 4)
	reverse_button_rect := remaining_rects[0]
	nudge_rect(&reverse_button_rect, 7, .right)
	ui_state.font_size = .m
	reverse_button := text_button("reverse@sampler-reverse-button", reverse_button_rect)

	pitch_knob_rect := remaining_rects[1]
	pitch_knob := knob("pitch@sampler-pitch-knob", &pitch_knob_rect)

	volume_knob_rect := remaining_rects[2]
	volume_knob := knob("volume@sampler-volume-knob", &volume_knob_rect)
}

slice_markers :: proc(sampler: ^Sampler_State, waveform_rect: Rect, track_num: u32) {
	if !(sampler.n_slices > 0) {
		return
	}
	for i in 0 ..< sampler.n_slices {
		slice := &sampler.slices[i]

		if slice.how_far < sampler.zoom_point ||
		   slice.how_far > sampler.zoom_point + (1 - sampler.zoom_amount) {continue}

		slice_position_ratio := (slice.how_far - sampler.zoom_point) / (1 - sampler.zoom_amount)
		slice_marker_x := waveform_rect.top_left.x + slice_position_ratio * rect_width(waveform_rect)
		slice_marker_top_y := waveform_rect.top_left.y
		slice_marker_bottom_y := waveform_rect.bottom_right.y
		slice_marker_rect := Rect {
			{f32(slice_marker_x), f32(slice_marker_top_y)},
			{f32(slice_marker_x + 2), f32(slice_marker_bottom_y)},
		}
		push_color(palette.grey.s_900)
		line(
			tprintf("slice-{}@sampler-{}-slice-{}-line", slice.which, track_num, slice.which),
			slice_marker_rect,
		)

		// Add drag handle of slice marker.
		handle_rect := Rect {
			{slice_marker_x - 7, slice_marker_top_y},
			{slice_marker_x + 7, slice_marker_top_y + 20},
		}
		push_color(palette.grey.s_500)
		ui_state.z_index = 7
		handle := button(
			tprintf("slice-{}@sampler-{}-slice-{}-handle", slice.which, track_num, slice.which),
			handle_rect,
		)

		if handle.double_clicked {
			remove_slice_maker(slice.which, sampler)
		}

		// ============ Handle dragging slice markers.=====================
		if handle.dragging {
			sampler.dragged_slice = i
			sampler.dragging_a_slice = true
		}
		// Continue drag (NOT dependent on handle.dragging!)
		if app.mouse.left_pressed && sampler.dragged_slice == i && sampler.dragging_a_slice {
			change_in_x := f32(app.mouse.pos.x - app.mouse.last_pos.x)
			visible_range := 1 - sampler.zoom_amount
			screen_delta := change_in_x / rect_width(waveform_rect)
			audio_delta := screen_delta * visible_range
			slice.how_far += audio_delta
			// Clamp to valid range
			slice.how_far = clamp(slice.how_far, 0, 1)
		}
		// End drag
		if !app.mouse.left_pressed {
			sampler.dragging_a_slice = false
		}
		ui_state.z_index = 0
	}
	clear_color_stack()

	// =================== Handle adding slice labels ======================
	sampler_slice_label :: proc(
		start_x, end_x: f32,
		waveform_rect: Rect,
		sampler: Sampler_State,
		slice_num: u32,
	) {
		midpoint_x := (start_x + end_x) / 2
		// Not at all precise positioning. Would need to account for word len to position correctly.
		note_rect := Rect {
			{midpoint_x - 10, waveform_rect.top_left.y},
			{midpoint_x + 10, waveform_rect.top_left.y + 30},
		}
		text_container(
			tprintf("{}@sampler-{}-slice-note-{}", slice_num, get_active_track(), slice_num),
			note_rect,
		)
	}
	this_x := waveform_rect.top_left.x
	// next_x := waveform_rect.top_left.x + sampler.slices[0].how_far * rect_width(waveform_rect)
	slice_screen_normalized := (sampler.slices[0].how_far - sampler.zoom_point) / (1 - sampler.zoom_amount)
	next_x := waveform_rect.top_left.x + slice_screen_normalized * rect_width(waveform_rect)
	ui_state.font_size = .xs

	// Add first lable
	sampler_slice_label(this_x, next_x, waveform_rect, sampler^, 0)
	// sampler_slice_label(this_x, next_x, waveform_rect, sampler^, 0)
	for j: u32 = 0; sampler.n_slices != 0 && j < sampler.n_slices - 1; j += 1 {
		this_slice_screen_normalized :=
			(sampler.slices[j].how_far - sampler.zoom_point) / (1 - sampler.zoom_amount)
		this_x := waveform_rect.top_left.x + this_slice_screen_normalized * rect_width(waveform_rect)

		next_slice_screen_normalized :=
			(sampler.slices[j + 1].how_far - sampler.zoom_point) / (1 - sampler.zoom_amount)
		next_x := waveform_rect.top_left.x + next_slice_screen_normalized * rect_width(waveform_rect)
		sampler_slice_label(this_x, next_x, waveform_rect, sampler^, j + 1)
	}
	// Add last label.
	if sampler.n_slices >= 1 {
		// this_x =
		// 	waveform_rect.top_left.x +
		// 	sampler.slices[sampler.n_slices - 1].how_far * rect_width(waveform_rect)
		last_slice_screen_normalized :=
			(sampler.slices[sampler.n_slices - 1].how_far - sampler.zoom_point) / (1 - sampler.zoom_amount)
		this_x = waveform_rect.top_left.x + last_slice_screen_normalized * rect_width(waveform_rect)
		next_x = waveform_rect.bottom_right.x
		sampler_slice_label(this_x, next_x, waveform_rect, sampler^, sampler.n_slices)
	}
}

sampler :: proc(id_string: string, rect: ^Rect, track_num: u32) -> Sampler_Signals {
	sampler_name := get_name_from_id_string(id_string)
	ui_state.z_index = 2
	defer ui_state.z_index = 0

	sampler_container := draggable_container(
		tprintf("sampler-container@{}-container", get_id_from_id_string(id_string)),
		rect,
	)
	sampler_rect := sampler_container.container.box.rect

	left_controls_rect := cut_left(&sampler_rect, {.Percent, 0.13})
	left_controls_container := container("left-controls@left-controls-sampler", left_controls_rect).box
	sampler_left_controls(&left_controls_container.rect)

	bottom_controls_rect := cut_bottom(&sampler_rect, {.Percent, 0.1})
	bottom_controls_container := container(
		tprintf("container@bottom-controls-container"),
		bottom_controls_rect,
	)

	sampler_bottom_controls(&bottom_controls_container.box.rect, track_num)

	active_track := get_active_track()
	if app.audio_state.tracks[active_track].sound != nil &&
	   (app.audio_state.tracks[active_track].pcm_data.left_channel == nil ||
			   len(app.audio_state.tracks[active_track].pcm_data.left_channel) == 0) {
		store_track_pcm_data(active_track)
	}

	// Only render waveform data is a sound is loaded into a track.
	if app.audio_state.tracks[active_track].sound == nil {
		ui_state.font_size = .xl
		text_container("No sound loaded@sampler-info-no-sound", sampler_rect)
		ui_state.font_size = .m
		return Sampler_Signals{container_signals = sampler_container}
	}

	waveform_container := clickable_container(
		tprintf(
			"{}-waveform-container@{}-waveform-container",
			sampler_name,
			get_id_from_id_string(id_string),
		),
		sampler_rect,
	)

	decrease_zoom :: proc(sampler: ^Sampler_State) {
		zoom_factor := 1 / (1 - sampler.zoom_amount)
		zoom_factor /= 1.2
		sampler.zoom_amount = clamp(1 - (1 / zoom_factor), 0, 0.99999)
	}
	increase_zoom :: proc(sampler: ^Sampler_State) {
		zoom_factor := 1 / (1 - sampler.zoom_amount)
		zoom_factor *= 1.2
		// sampler.zoom_amount = clamp(sampler.zoom_amount + zoom_factor, 0, 0.99999)
		sampler.zoom_amount = clamp(1 - (1 / zoom_factor), 0, 0.99999)
	}

	// =========== Handle zooming in on the waveform.=========================
	waveform_rect := waveform_container.box.rect
	track_num := get_active_track()
	sampler := app.samplers[track_num]
	if waveform_container.scrolled {
		// ==== HELP FROM CLAUDE WITH PROPPER ZOOMING ======
		// Calculate where the mouse is in the current visible waveform (0-1 range)
		mouse_screen_normalized := map_range(
			waveform_rect.top_left.x,
			waveform_rect.bottom_right.x,
			0,
			1,
			f32(app.mouse.pos.x),
		)

		// Get current zoom values
		old_zoom_amount := sampler.zoom_amount
		old_visible_width := 1.0 - old_zoom_amount

		// Calculate the waveform position under the mouse BEFORE zooming
		// This is the key: we need to know what part of the actual waveform is under the cursor
		waveform_position_under_mouse := sampler.zoom_point + mouse_screen_normalized * old_visible_width

		// Apply zoom change
		if app.mouse.wheel.y < 0 {
			decrease_zoom(sampler)
		} else if app.mouse.wheel.y > 0 {
			increase_zoom(sampler)
		}

		// Calculate new visible width after zoom
		new_visible_width := 1.0 - sampler.zoom_amount

		// Calculate new zoom_point to keep the same waveform position under the mouse
		// We want: waveform_position_under_mouse = new_zoom_point + mouse_screen_normalized * new_visible_width
		// Solving for new_zoom_point:
		sampler.zoom_point = waveform_position_under_mouse - mouse_screen_normalized * new_visible_width

		// Clamp zoom_point to valid range
		sampler.zoom_point = clamp(sampler.zoom_point, 0, 1 - new_visible_width)

		printfln("changed zoom - point: {}  amount: {}", sampler.zoom_point, sampler.zoom_amount)
	}

	// Handle adding slices.
	if sampler.mode == .slice {
		if !sampler.dragging_a_slice && waveform_container.clicked {
			mouse_screen_normalized := map_range(
				waveform_rect.top_left.x,
				waveform_rect.bottom_right.x,
				0,
				1,
				f32(app.mouse.pos.x),
			)

			// Convert to waveform position
			how_far := sampler.zoom_point + mouse_screen_normalized * (1 - sampler.zoom_amount)
			add_slice_marker(how_far, sampler)
		}
		slice_markers(sampler, waveform_container.box.rect, track_num)
	}

	cut_top(&waveform_container.box.rect, {.Pixels, 30})
	return Sampler_Signals{container_signals = sampler_container}
}

// Binary search to add it into the list, and slide the rest of the elements over to maintain order.
add_slice_marker :: proc(new_value: f32, sampler: ^Sampler_State) {
	assert(sampler.n_slices < len(sampler.slices), "Tried to insert slice, but we have no more capacity!")

	new_slice := Sampler_Slice {
		how_far = new_value,
		which   = sampler.n_slices,
	}

	// Find insertion position using binary search.
	left, right := u32(0), sampler.n_slices
	for left < right {
		mid := (left + right) / 2
		if sampler.slices[mid].how_far < new_value {
			left = mid + 1
		} else {
			right = mid
		}
	}

	// 'left' is now the insertion position
	insert_pos := left

	// Shift elements if not inserting at the end.
	if insert_pos < sampler.n_slices {
		// Copy from insert_pos to insert_pos+1, shifting right.
		mem.copy(
			&sampler.slices[insert_pos + 1],
			&sampler.slices[insert_pos],
			size_of(Sampler_Slice) * int(sampler.n_slices - insert_pos),
		)
	}

	sampler.slices[insert_pos] = new_slice
	sampler.n_slices += 1
}

remove_slice_maker :: proc(slice_num: u32, sampler: ^Sampler_State) {
	if sampler.n_slices == 1 {
		sampler.slices[0] = {}
		sampler.n_slices = 0
	}
	for i in 0 ..< sampler.n_slices {
		slice := sampler.slices[i]
		if slice.which == slice_num {
			slice = {}
			if !(u32(i) == sampler.n_slices - 1) {
				mem.copy(
					&sampler.slices[i],
					&sampler.slices[i + 1],
					int(size_of(Sampler_Slice) * (sampler.n_slices - u32(i) - 1)),
				)
			}
			sampler.n_slices -= 1
		}
	}
}
