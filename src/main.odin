package main
import "base:intrinsics"
import "core:fmt"
import "core:io"
import "core:math"
import alg "core:math/linalg"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:os"
import s "core:strings"
import "core:thread"
import "core:time"
import gl "vendor:OpenGL"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"
import sttf "vendor:sdl2/ttf"

println :: fmt.println
printf :: fmt.printf
aprintf :: fmt.aprintf
WINDOW_WIDTH :: 3000 * 0.5
WINDOW_HEIGHT :: 2000 * 0.5
ASPECT_RATIO: f32 : 16.0 / 10.0

// Global UI data
// theres are i32 because of SDL fuckery, they should be u32
window: ^sdl.Window
wx: ^i32 = new(i32)
wy: ^i32 = new(i32)
ui_state: ^UI_State = new(UI_State)
audio_state: ^Audio_State = new(Audio_State)
ui_font: ^sttf.Font

char_map := new(u32)

quad_vbuffer := new(u32)
quad_vabuffer := new(u32)
quad_shader_program: u32

text_vbuffer := new(u32)
text_vabuffer := new(u32)

slider_value: f32 = 30
slider_max: f32 = 100

// Global audio data
N_TRACKS :: 10

setup_window :: proc() -> (^sdl.Window, sdl.GLContext) {
	sdl.Init({.AUDIO, .EVENTS, .TIMER})

	window_flags :=
		sdl.WINDOW_OPENGL | sdl.WINDOW_RESIZABLE | sdl.WINDOW_ALLOW_HIGHDPI | sdl.WINDOW_UTILITY
	window := sdl.CreateWindow(
		"Odin SDL2 Demo",
		sdl.WINDOWPOS_UNDEFINED,
		sdl.WINDOWPOS_UNDEFINED,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		window_flags,
	)
	if window == nil {
		panic("Failed to create window")
	}

	// Set OpenGL attributes after SDL initialization
	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
	sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, gl.CONTEXT_CORE_PROFILE_BIT)
	sdl.GL_SetAttribute(.MULTISAMPLEBUFFERS, 1)
	sdl.GL_SetAttribute(.MULTISAMPLESAMPLES, 8)

	gl_context := sdl.GL_CreateContext(window)
	if gl_context == nil {
		panic("Failed to create OpenGL context")
	}
	sdl.GL_MakeCurrent(window, gl_context)

	gl.load_up_to(4, 3, sdl.gl_set_proc_address)

	// Enable OpenGL settings
	gl.Hint(gl.LINE_SMOOTH_HINT, gl.NICEST)
	gl.Hint(gl.POLYGON_SMOOTH_HINT, gl.NICEST)
	gl.Enable(gl.LINE_SMOOTH)
	gl.Enable(gl.POLYGON_SMOOTH)
	gl.Enable(gl.MULTISAMPLE)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	return window, gl_context
}

slider_volumes: [10]f32 = {10, 20, 30, 40, 50, 60, 70, 80, 90, 100}

ui_vertex_shader_data :: #load("shaders/vertex_shader.glsl")
ui_pixel_shader_data :: #load("shaders/fragment_shader.glsl")

main :: proc() {
	// setup state for UI
	ui_state.rect_stack = make([dynamic]^Rect)
	root_rect := new(Rect)
	append(&ui_state.rect_stack, root_rect)
	ui_state.box_cache = make(map[string]^Box)
	ui_state.temp_boxes = make([dynamic]^Box)
	ui_state.first_frame = true
	tmp, gl_context := setup_window()
	window = tmp

	// setup audio stuff
	setup_audio_engine(audio_engine)

	gl.GenVertexArrays(1, quad_vabuffer)
	gl.GenVertexArrays(1, text_vabuffer)
	create_vbuffer(quad_vbuffer, nil, 500_000)
	quad_shader_program, shader_ok := gl.load_shaders_source(
		string(ui_vertex_shader_data),
		string(ui_pixel_shader_data),
	)
	assert(shader_ok)
	bind_shader(quad_shader_program)
	set_shader_vec2(quad_shader_program, "screen_res", {f32(WINDOW_WIDTH), f32(WINDOW_HEIGHT)})

	// ui_state.char_map = create_font_map(30)
	// text_proj := alg.matrix_ortho3d_f32(0, WINDOW_WIDTH, WINDOW_HEIGHT, 0, -1, 1)
	// create_vbuffer(text_vbuffer, nil, 10_000 * size_of(f32))

	setup_for_quads(&quad_shader_program)
	sdl.GetWindowSize(window, wx, wy)
	app_loop: for {
		if register_resize() {
			set_shader_vec2(quad_shader_program, "screen_res", {f32(wx^), f32(wy^)})
		}
		root_rect.top_left = {0, 0}
		root_rect.bottom_right = {f32(wx^), f32(wy^)}
		event: sdl.Event
		reset_mouse_state()
		for sdl.PollEvent(&event) {
			if !handle_input(event) {
				break app_loop
			}
		}
		create_ui()
		clear_screen()
		render_ui()
		reset_renderer_data()
		sdl.GL_SwapWindow(window)
		free_all(context.temp_allocator)
		free_all()
	}
}

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
		switch event.button.button {
		case sdl.BUTTON_LEFT:
			ui_state.mouse.left_pressed = true
		case sdl.BUTTON_RIGHT:
			ui_state.mouse.right_pressed = true
		}
	case .MOUSEBUTTONUP:
		switch event.button.button {
		case sdl.BUTTON_LEFT:
			ui_state.mouse.left_pressed = false
		case sdl.BUTTON_RIGHT:
			ui_state.mouse.right_pressed = false
		}
	case .MOUSEMOTION:
		sdl.GetMouseState(&ui_state.mouse.pos.x, &ui_state.mouse.pos.y)
	case .MOUSEWHEEL:
		ui_state.mouse.wheel.x = cast(i8)event.wheel.x
		ui_state.mouse.wheel.y = cast(i8)event.wheel.y
	case .DROPFILE:
		which, on_track := dropped_on_track()
		assert(on_track)
		if on_track {
			println("dropped on track:", which)
			set_track_sound(event.drop.file, which)
		}
	}
	return true
}

register_resize :: proc() -> bool {
	old_width, old_height := wx^, wy^
	sdl.GetWindowSize(window, wx, wy)
	if old_width != wx^ || old_height != wy^ {
		gl.Viewport(0, 0, wx^, wy^)
		return true
	}
	return false
}

reset_mouse_state :: proc() {
	ui_state.mouse.wheel = {0, 0}
}
