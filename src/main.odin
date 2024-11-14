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
// import builder "ui_builder"
// import core "ui_core"
import gl "vendor:OpenGL"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"
import sttf "vendor:sdl2/ttf"

println :: fmt.println
WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080

// theres are i32 because of SDL fuckery, they should be u32
n_boxes: u64 = 0
wx: ^i32 = new(i32)
wy: ^i32 = new(i32)
ui_state: ^UI_State = new(UI_State)
ui_font: ^sttf.Font
root_box := Box {
	rect              = {{20, 20}, {cast(f32)wx^, cast(f32)wy^}},
	id_string         = "root",
	child_layout_axis = .X,
	pref_size         = {
		Size{kind = .Pixels, value = cast(f32)WINDOW_WIDTH},
		Size{kind = .Pixels, value = cast(f32)WINDOW_HEIGHT},
	},
}
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
	// disable_layout(0)

	enable_layout(1)
	layout_vbuffer(1, 4, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, color))
	// disable_layout(1)
	bind_shader(shader^)
}

tracker_track :: proc(which_track: u32, slider_value: ^f32) {
	name := fmt.aprintf("track_%d", which_track)
	// // need a smart way to set the width of tracks
	track_size: [2]Size = {
		Size{kind = .Pecent_Of_Parent, value = 0.125},
		Size{kind = .Pecent_Of_Parent, value = 1},
	}
	track_container := box_from_cache(
		{.Draw, .Draw_Background},
		fmt.aprintf("%s_container", name, context.temp_allocator),
		track_size,
	)
	append(&ui_state.temp_boxes, track_container)
	track_container.child_layout_axis = .Y
	layout_push_parent(track_container)

	tracker_notes_size: [2]Size = {
		Size{kind = .Pecent_Of_Parent, value = 1},
		Size{kind = .Pecent_Of_Parent, value = 0.7},
	}
	tracker_steps := box_from_cache(
		{},
		fmt.aprintf("%s_tracker_steps", name, context.temp_allocator),
		tracker_notes_size,
	)

	// controls_container := box_from_cache(
	// 	{},
	// 	fmt.aprintf("%s_controls_container", name, context.temp_allocator),
	// 	{{kind = .Pecent_Of_Parent, value = 1}, {kind = .Pecent_Of_Parent, value = 0.3}},
	// )
	slider := slider(
		{Size{.Pecent_Of_Parent, 0.2, 1}, Size{.Pecent_Of_Parent, 0.3, 1}}, // Need to be careful with the size.strictness which = 1 here.
		fmt.aprintf("%s_volume_slider", name, context.temp_allocator),
		slider_value^,
		slider_max,
	)
	button_container := box_from_cache(
		{},
		fmt.aprintf("%s_button_container", name, context.temp_allocator),
		{{kind = .Pecent_Of_Parent, value = 0.2}, {kind = .Pecent_Of_Parent, value = 0.05}},
	)
	button_container.child_layout_axis = .X
	layout_push_parent(button_container)

	// this is arbitrary
	x_space(0.48, fmt.aprintf("%s_space", name, context.temp_allocator))
	b := button(
		fmt.aprintf("%s_play_button1", name, context.temp_allocator),
		{{kind = .Pecent_Of_Parent, value = 1}, {kind = .Pecent_Of_Parent, value = 1}},
	)

	layout_pop_parent()
	layout_pop_parent()
	if slider.track_signals.scrolled {
		slider_value^ = calc_slider_grip_val(slider_value^, slider_max)
		ma.sound_set_volume(
			engine_sounds[which_track],
			calc_slider_volume(0, slider_max, 0, 1, slider_value^),
		)
	}
	if b.clicked {
		toggle_sound(engine_sounds[which_track])
	}
	draw_text("sau paulo", b.box.rect[0].x, b.box.rect[0].y + b.box.calc_size.y / 1.5)
}

sv1: f32 = 10
sv2: f32 = 10
sv3: f32 = 10
draw_ui :: proc(shader_program: ^u32) {
	root_box.child_layout_axis = .X
	layout_push_parent(&root_box)
	tracker_track(0, &sv1)
	tracker_track(1, &sv2)
	layout_pop_parent()

	layout_from_root(&root_box, Axis.Y)
	layout_from_root(&root_box, Axis.X)
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
	ui_state.layout_stack = make(Layout_Stack)
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
	create_ibuffer(index_buffer, nil, 1000 * size_of(u32))
	setup_for_quads(&quad_shader_program)

	ui_state.char_map = create_font_map(30)
	text_proj := alg.matrix_ortho3d_f32(0, WINDOW_WIDTH, WINDOW_HEIGHT, 0, -1, 1)
	// this will probably need to be dynamically sized in the future...
	create_vbuffer(text_vbuffer, nil, 1000 * size_of(f32))

	sdl.GetWindowSize(window, wx, wy)
	mx, my: i32
	app_loop: for {
		start := sdl.GetTicks()
		register_resize(window)
		reset_ui_state()
		event: sdl.Event
		for sdl.PollEvent(&event) {
			if !handle_input(event) {
				println("quit event received, exiting...")
				break app_loop
			}
		}
		clear()
		setup_for_quads(&quad_shader_program)
		draw_ui(&quad_shader_program)
		reset_renderer_data()
		register_resize(window)
		sdl.GL_SwapWindow(window)
		ui_state.first_frame = false
	}
}
