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
import "core:thread"
import "core:time"
import builder "ui_builder"
import core "ui_core"
import gl "vendor:OpenGL"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"
import sttf "vendor:sdl2/ttf"

println :: fmt.println
WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080

wx, wy: i32
ui_state: ^core.UI_State = new(core.UI_State)
ui_font: ^sttf.Font
root_box := core.Box {
	rect              = {{20, 20}, {cast(f32)wx, cast(f32)wy}},
	id_string         = "root",
	child_layout_axis = .X,
	pref_size         = {
		core.Size{kind = .Pixels, value = cast(f32)WINDOW_WIDTH},
		core.Size{kind = .Pixels, value = cast(f32)WINDOW_HEIGHT},
	},
}

// returns if we should exit the app
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
	sdl.GetWindowSize(window, &wx, &wy)
	wxf := cast(f32)wx
	wyf := cast(f32)wy
	gl.Viewport(0, 0, wx, wy)
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

setup_for_quads :: proc(vbuffer: ^u32, vabuffer: ^u32, shader: ^u32) {
	gl.BindVertexArray(vabuffer^)
	core.enable_layout(0)
	core.layout_vbuffer(
		0,
		2,
		gl.FLOAT,
		gl.FALSE,
		size_of(core.Vertex),
		offset_of(core.Vertex, pos),
	)

	core.enable_layout(1)
	core.layout_vbuffer(
		1,
		4,
		gl.FLOAT,
		gl.FALSE,
		size_of(core.Vertex),
		offset_of(core.Vertex, color),
	)
	core.bind_shader(shader^)
}

sv1: f32 = 10
sv2: f32 = 10
sv3: f32 = 10
draw_quads :: proc(slider_value, slider_max: ^f32, vbuffer, ibuffer, program: ^u32) {

	root_box.child_layout_axis = .X
	core.layout_push_parent(&ui_state.layout_stack, &root_box)

	slider_size: [2]core.Size = {
		core.Size{kind = .Pecent_Of_Parent, value = 0.2},
		core.Size{kind = .Pecent_Of_Parent, value = 0.8},
	}

	player_size: [2]core.Size = {
		core.Size{kind = .Pecent_Of_Parent, value = 0.2},
		core.Size{kind = .Pecent_Of_Parent, value = 0.5},
	}

	player1_container := core.box_from_cache({}, ui_state, "player1_container", player_size)
	player1_container.child_layout_axis = .Y
	core.layout_push_parent(&ui_state.layout_stack, player1_container)
	// builder.x_space(ui_state, 0.1, "player1_space1")
	slider1 := builder.slider(ui_state, slider_size, "slider1_rect", sv1, slider_max^)
	b1 := builder.button(
		ui_state,
		"button1",
		{{kind = .Pecent_Of_Parent, value = 0.2}, {kind = .Pecent_Of_Parent, value = 0.1}},
	)
	core.layout_pop_parent(&ui_state.layout_stack)

	player2_container := core.box_from_cache({}, ui_state, "player2_container", player_size)
	player2_container.child_layout_axis = .Y
	core.layout_push_parent(&ui_state.layout_stack, player2_container)
	slider2 := builder.slider(ui_state, slider_size, "slider2_rect", sv2, slider_max^)
	b2 := builder.button(
		ui_state,
		"button2",
		{{kind = .Pecent_Of_Parent, value = 0.2}, {kind = .Pecent_Of_Parent, value = 0.1}},
	)
	core.layout_pop_parent(&ui_state.layout_stack)


	if slider1.track_signals.scrolled {
		sv1 += -3 * cast(f32)ui_state.mouse.wheel.y
	}
	if slider2.track_signals.scrolled {
		sv2 += -3 * cast(f32)ui_state.mouse.wheel.y
	}
	if b1.clicked {
		println("button 1 clicked")
	}
	if b2.clicked {
		println("button 2 clicked")
	}


	core.layout_pop_parent(&ui_state.layout_stack)
	core.layout_from_root(ui_state^, &root_box, core.Axis.Y)
	core.layout_from_root(ui_state^, &root_box, core.Axis.X)
	if !ui_state.first_frame {
		core.render_boxes(ui_state)
		core.populate_ibuffer(
			ibuffer,
			raw_data(ui_state.renderer_data.indices),
			ui_state.renderer_data.n_quads * 6,
		)
		core.populate_vbuffer(
			vbuffer,
			0,
			raw_data(ui_state.renderer_data.raw_vertices),
			// no idea why i need to 4x this...
			4 * ui_state.renderer_data.n_quads * size_of(core.Vertex),
		)
		proj := alg.matrix_ortho3d_f32(0, cast(f32)wx, cast(f32)wy, 0, -1, 1)
		core.set_shader_matrix4(program^, "proj", &proj)
		core.draw(
			cast(i32)(ui_state.renderer_data.n_quads * 6),
			raw_data(ui_state.renderer_data.indices),
		)
	}
}

main :: proc() {
	ui_state.renderer_data = new(core.Renderer_Data)
	ui_state.layout_stack = make(core.Layout_Stack)
	ui_state.box_cache = make(map[string]^core.Box)
	ui_state.temp_boxes = make([dynamic]^core.Box)
	ui_state.first_frame = true

	window, gl_context := setup_window()

	// files := new([dynamic]string)
	// append(files, "/home/lucas/Music/test_sounds/StarWars3.wav")
	// setup_and_play(files^)
	// ma.event_signal(&stop_event)
	// ma.event_wait(&stop_event)
	// println("Press [Enter] to stop the program")
	// buf: [1]byte
	// os.read(os.stdin, buf[:])

	// create data to run setup for quad drawing
	quad_vabuffer, text_vabuffer: u32
	quad_vbuffer, text_vbuffer: u32
	vabuffers: [^]u32
	gl.GenVertexArrays(1, &quad_vabuffer)
	gl.GenVertexArrays(1, &text_vabuffer)
	core.create_vbuffer(&quad_vbuffer, nil, 1000 * size_of(core.Vertex))
	program := core.create_shader(
		"src/shaders/vertex_shader.glsl",
		"src/shaders/fragment_shader.glsl",
	)
	index_buffer: u32
	core.create_ibuffer(&index_buffer, nil, 1000 * size_of(u32))
	setup_for_quads(&quad_vbuffer, &quad_vabuffer, &program)

	char_map := core.create_font_map(30)
	text_proj := alg.matrix_ortho3d_f32(0, WINDOW_WIDTH, WINDOW_HEIGHT, 0, -1, 1)

	// this will probably need to be dynamically sized in the future...
	core.create_vbuffer(&text_vbuffer, nil, 1000 * size_of(f32))

	sdl.GetWindowSize(window, &wx, &wy)
	slider_value: f32 = 30
	slider_max: f32 = 100
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
		core.clear()
		core.draw_text(
			"bruh it works",
			&text_vbuffer,
			&text_vabuffer,
			char_map,
			{cast(u32)wx, cast(u32)wy},
		)
		setup_for_quads(&quad_vbuffer, &quad_vabuffer, &program)
		draw_quads(&slider_value, &slider_max, &quad_vbuffer, &index_buffer, &program)
		reset_renderer_data()
		register_resize(window)
		sdl.GL_SwapWindow(window)
		ui_state.first_frame = false
	}
}
