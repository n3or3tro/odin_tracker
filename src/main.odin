package main
import "base:intrinsics"
import "core:fmt"
import "core:io"
import "core:math"
import alg "core:math/linalg"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:os"
import "core:strings"
import sys_l "core:sys/linux"
import "core:thread"
import "core:time"
import osd "third_party/osdialog"
import gl "vendor:OpenGL"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"
import sttf "vendor:sdl2/ttf"

println :: fmt.println
WINDOW_WIDTH :: 2000
WINDOW_HEIGHT :: 1500
n_boxes: u64 = 0
// theres are i32 because of SDL fuckery, they should be u32
wx: ^i32 = new(i32)
wy: ^i32 = new(i32)
ui_state: ^UI_State = new(UI_State)
ui_font: ^sttf.Font
text_vbuffer := new(u32)
text_vabuffer := new(u32)
char_map := new(u32)
quad_vbuffer := new(u32)
quad_vabuffer := new(u32)
index_buffer := new(u32)

slider_value: f32 = 30
slider_max: f32 = 100

quad_shader_program: u32
handle_input :: proc(event: sdl.Event) -> bool {
	#partial switch event.type {
	case .KEYDOWN:
		#partial switch event.key.keysym.sym {
		case .ESCAPE:
			return false
		}
	case .QUIT:
		return false
	case .MOUSEBUTTONDOWN:
		if event.button.button == sdl.BUTTON_LEFT {
			ui_state.mouse.left_pressed = true
		}
		if event.button.button == sdl.BUTTON_RIGHT {
			ui_state.mouse.right_pressed = true
		}
	case .MOUSEBUTTONUP:
		if event.button.button == sdl.BUTTON_LEFT {
			ui_state.mouse.left_released = true
		}
		if event.button.button == sdl.BUTTON_RIGHT {
			ui_state.mouse.right_released = true
		}
	case .MOUSEMOTION:
		sdl.GetMouseState(&ui_state.mouse.pos.x, &ui_state.mouse.pos.y)
	case .MOUSEWHEEL:
		ui_state.mouse.wheel.x = cast(i8)event.wheel.x
		ui_state.mouse.wheel.y = cast(i8)event.wheel.y
	case .DROPFILE:
		// probably have some logic to only pickup files dropped in the right location
		println("file dropped: {}", event.drop.file)
	}
	return true
}

setup_window :: proc() -> (^sdl.Window, sdl.GLContext) {
	window_flags :=
		sdl.WINDOW_OPENGL | sdl.WINDOW_RESIZABLE | sdl.WINDOW_ALLOW_HIGHDPI | sdl.WINDOW_UTILITY

	window := sdl.CreateWindow(
		"Odin sdl2 Demo",
		sdl.WINDOWPOS_UNDEFINED,
		sdl.WINDOWPOS_UNDEFINED,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		window_flags,
	)
	if window == nil {
		panic("Failed to create window")
	}
	sdl.GL_SetAttribute(.MULTISAMPLEBUFFERS, 1)
	sdl.GL_SetAttribute(.MULTISAMPLESAMPLES, 8)

	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
	sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 1)

	sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, gl.CONTEXT_CORE_PROFILE_BIT)

	sdl.Init({.AUDIO, .EVENTS, .TIMER})

	gl.load_up_to(4, 1, sdl.gl_set_proc_address)
	gl_context := sdl.GL_CreateContext(window)
	sdl.GL_MakeCurrent(window, gl_context)

	gl.Hint(gl.LINE_SMOOTH_HINT, gl.NICEST)
	gl.Hint(gl.POLYGON_SMOOTH_HINT, gl.NICEST)
	gl.Enable(gl.LINE_SMOOTH)
	gl.Enable(gl.POLYGON_SMOOTH)
	gl.Enable(gl.MULTISAMPLE)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	return window, gl_context
}

register_resize :: proc(window: ^sdl.Window) {
	sdl.GetWindowSize(window, wx, wy)
	gl.Viewport(0, 0, wx^, wy^)
}

reset_renderer_data :: proc() {
	ui_state.renderer_data.n_quads = 0
	clear_dynamic_array(&ui_state.renderer_data.indices)
	clear_dynamic_array(&ui_state.renderer_data.vertices)
	clear_dynamic_array(&ui_state.renderer_data.raw_vertices)
	clear_dynamic_array(&ui_state.temp_boxes)
}

// resets things which shouldn't hold across frames
reset_ui_state :: proc() {
	ui_state.mouse.left_pressed = false
	ui_state.mouse.right_pressed = false
	ui_state.mouse.left_released = true
	ui_state.mouse.right_released = true
	ui_state.mouse.wheel = {0, 0}
}

setup_for_quads :: proc(shader: ^u32) {
	gl.BindVertexArray(quad_vabuffer^)
	enable_layout(0)
	layout_vbuffer(0, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, pos))

	enable_layout(1)
	layout_vbuffer(1, 4, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, color))
	bind_shader(shader^)
}

tracker_track :: proc(which_track: u32, slider_value: ^f32) {
}

handle_track_control_interactions :: proc(t_controls: ^Track_Control_Signals, which: u32) {
	if t_controls.track_signals.scrolled {
		slider_volumes[which] = calc_slider_grip_val(slider_volumes[which], 100)
		ma.sound_set_volume(engine_sounds[which], map_range(0, 100, 0, 1, slider_volumes[which]))
	}
	if t_controls.button_signals.play_signals.clicked {
		toggle_sound(engine_sounds[which])
	}
	if t_controls.button_signals.file_load_signals.clicked {
		// println(osd.path(.Open_Dir))
	}
}
handle_track_steps_interactions :: proc(track: [33]Box_Signals) {
	for step in track {
		if step.hovering {
			println("hovering over:", step.box.id_string)
		}
	}
}

// Obviously not a complete track, but as complete-ish for now :).
create_track :: proc(which: u32) -> [33]Box_Signals {
	track_container := cut_rect(top_rect(), RectCut{Size{.Pixels, 200}, .Left})
	track_controller_container := cut_rect(&track_container, RectCut{Size{.Percent, 0.3}, .Bottom})
	push_parent_rect(&track_container)
	push_parent_rect(&track_controller_container)
	track_controls_0 := track_controls(
		fmt.aprintf("track%d_controls@1", which),
		&track_controller_container,
		slider_volumes[which],
	)
	pop_parent_rect()
	track_step_container := cut_rect(top_rect(), {Size{.Percent, 0.95}, .Top})
	steps := track_steps(fmt.aprintf("track_steps%d@1", which), &track_step_container)
	pop_parent_rect()

	handle_track_steps_interactions(steps)
	handle_track_control_interactions(&track_controls_0, which)

	return steps
}

slider_volumes: [10]f32 = {10, 20, 30, 40, 50, 60, 70, 80, 90, 100}
draw_ui :: proc(shader_program: ^u32) {
	steps: [33]Box_Signals
	for i in 0 ..= 9 {
		steps = create_track(u32(i))
		spacer(fmt.aprintf("track_spacer%s", i), RectCut{Size{.Pixels, 2}, .Left})
	}

	if !ui_state.first_frame {
		render_boxes(ui_state)
		populate_ibuffer(
			index_buffer,
			raw_data(ui_state.renderer_data.indices),
			ui_state.renderer_data.n_quads * 6,
		)
		populate_vbuffer(
			quad_vabuffer,
			0,
			raw_data(ui_state.renderer_data.raw_vertices),
			// no idea why i need to 4x this...
			4 * ui_state.renderer_data.n_quads * size_of(Vertex),
		)
		proj := alg.matrix_ortho3d_f32(0, cast(f32)wx^, cast(f32)wy^, 0, -1, 1)
		set_shader_matrix4(shader_program^, "proj", &proj)
		draw(
			cast(i32)(ui_state.renderer_data.n_quads * 6),
			raw_data(ui_state.renderer_data.indices),
		)
	}
}

main :: proc() {
	// setup state for UI
	ui_state.renderer_data = new(Renderer_Data)
	ui_state.rect_stack = make([dynamic]^Rect)
	ui_state.rect_hash_cache = make(map[string][]byte)
	root_rect := new(Rect)
	append(&ui_state.rect_stack, root_rect)

	ui_state.box_cache = make(map[string]^Box)
	ui_state.temp_boxes = make([dynamic]^Box)
	ui_state.first_frame = true
	window, gl_context := setup_window()

	// setup audio stuff
	setup_audio_engine(audio_engine)
	load_files()

	gl.GenVertexArrays(1, quad_vabuffer)
	gl.GenVertexArrays(1, text_vabuffer)
	create_vbuffer(quad_vbuffer, nil, 1000 * size_of(Vertex))
	quad_shader_program = create_shader(
		"src/shaders/vertex_shader.glsl",
		"src/shaders/fragment_shader.glsl",
	)
	create_ibuffer(index_buffer, nil, 100_000 * size_of(u32))
	setup_for_quads(&quad_shader_program)

	ui_state.char_map = create_font_map(30)
	text_proj := alg.matrix_ortho3d_f32(0, WINDOW_WIDTH, WINDOW_HEIGHT, 0, -1, 1)
	// this will probably need to be dynamically sized in the future...
	create_vbuffer(text_vbuffer, nil, 100_000 * size_of(f32))

	sdl.GetWindowSize(window, wx, wy)
	mx, my: i32
	println("about to start event loop, top rect is:", top_rect(), "\n")
	app_loop: for {
		root_rect.top_left = {0, 0}
		reset_ui_state()
		event: sdl.Event
		for sdl.PollEvent(&event) {
			if !handle_input(event) {
				println("quit event received, exiting...")
				break app_loop
			}
		}
		root_rect.bottom_right = {WINDOW_WIDTH, WINDOW_HEIGHT}
		clear()
		setup_for_quads(&quad_shader_program)
		draw_ui(&quad_shader_program)
		reset_renderer_data()
		register_resize(window)
		sdl.GL_SwapWindow(window)
		ui_state.first_frame = false
	}
}
