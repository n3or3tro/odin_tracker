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
import "core:sync"
import "core:thread"
import "core:time"
import gl "vendor:OpenGL"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"
import sttf "vendor:sdl2/ttf"

println :: fmt.println
printf :: fmt.printf
aprintf :: fmt.aprintf
WINDOW_WIDTH := 3000 * ui_scale
WINDOW_HEIGHT := 2000 * ui_scale
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
text_shader_program: u32

text_vbuffer := new(u32)
text_vabuffer := new(u32)

slider_value: f32 = 30
slider_max: f32 = 100

ui_scale: f32 = 0.8

// Used to tell the core layer to override some value
// of a box that's in the cache. Useful for parts of the code
// where the box isn't easilly accessible (like in audio related stuff).
override_color := false


// The idea is that the UI and other threads will update this queue which will be 
// repeatedly checked by the audio thread.
// Global audio data
N_TRACKS :: 10

setup_window :: proc() -> (^sdl.Window, sdl.GLContext) {
	// create_font_glyph()
	sdl.Init({.AUDIO, .EVENTS, .TIMER})

	window_flags :=
		sdl.WINDOW_OPENGL | sdl.WINDOW_RESIZABLE | sdl.WINDOW_ALLOW_HIGHDPI | sdl.WINDOW_UTILITY
	window := sdl.CreateWindow(
		"Odin SDL2 Demo",
		sdl.WINDOWPOS_UNDEFINED,
		sdl.WINDOWPOS_UNDEFINED,
		i32(WINDOW_WIDTH),
		i32(WINDOW_HEIGHT),
		window_flags,
	)
	if window == nil {
		panic("Failed to create window")
	}

	// Set OpenGL attributes after SDL initialization
	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
	sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 1)
	sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, gl.CONTEXT_CORE_PROFILE_BIT)
	sdl.GL_SetAttribute(.MULTISAMPLEBUFFERS, 1)
	sdl.GL_SetAttribute(.MULTISAMPLESAMPLES, 8)

	gl_context := sdl.GL_CreateContext(window)
	if gl_context == nil {
		panic("Failed to create OpenGL context")
	}
	sdl.GL_MakeCurrent(window, gl_context)

	gl.load_up_to(4, 1, sdl.gl_set_proc_address)

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

text_vertex_shader_data :: #load("shaders/text_vertex_shader.glsl")
text_pixel_shader_data :: #load("shaders/text_fragment_shader.glsl")

audio_thread :: proc() {
	println("started audio thread")
}

ui_thread :: proc() {
	// setup state for UI
	println("ui thread started")
	ui_state.rect_stack = make([dynamic]^Rect)
	ui_state.color_stack = make([dynamic]Color)
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
	program1, quad_shader_ok := gl.load_shaders_source(
		string(ui_vertex_shader_data),
		string(ui_pixel_shader_data),
	)
	assert(quad_shader_ok)
	quad_shader_program = program1

	program2, text_shader_ok := gl.load_shaders_source(
		string(text_vertex_shader_data),
		string(text_pixel_shader_data),
	)
	assert(text_shader_ok)
	text_shader_program = program2

	bind_shader(quad_shader_program)
	set_shader_vec2(quad_shader_program, "screen_res", {f32(WINDOW_WIDTH), f32(WINDOW_HEIGHT)})

	ui_state.char_map = create_font_map(30)
	create_vbuffer(text_vbuffer, nil, 100_000 * size_of(f32))

	setup_for_quads(&quad_shader_program)
	sdl.GetWindowSize(window, wx, wy)
	frame_num := 0
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
		clear_screen()
		create_ui()
		render_ui()
		render_text2()
		reset_renderer_data()
		sdl.GL_SwapWindow(window)
		if audio_state.playing {
			// at 120 fps, a 1/4 beat lasts for 30 frames. This is probably too hard coded
			// and fragile, should be made more robust...
			if frame_num % (30) == 0 {
				audio_state.curr_step = (audio_state.curr_step + 1) % 32 // 32 == n_steps per track.
				play_current_step()
			}
		}
		free_all(context.temp_allocator)
		free_all()
		frame_num += 1
	}
	println("ui thread is finished")
}

stupid_sem: sync.Atomic_Sema
main :: proc() {
	// map_colors()

	ui_thread()


	// The weird semaphore stuff is required because of Odin's bad thread
	// implementation, don't exactly understand the issue, but without it t1, will join
	// and finish before ui_thread has even started.

	// ui_thr := thread.create_and_start(proc() {
	// 	sync.atomic_sema_post(&stupid_sem)
	// 	ui_thread()
	// })
	// // waiting for ui_thread to start
	// sync.atomic_sema_wait_with_timeout(&stupid_sem, time.Millisecond * 200)

	// audio_thr := thread.create_and_start(proc() {
	// 	sync.atomic_sema_post(&stupid_sem)
	// 	audio_thread()
	// })
	// // waiting for audio_thread to start
	// sync.atomic_sema_wait_with_timeout(&stupid_sem, time.Millisecond * 200)

	// thread.join(ui_thr)
	// thread.join(audio_thr)
	// println(main_color)
}

resize_window :: proc() {
	// sdl.SetWindowSize(window, wx^, wy^)
	set_shader_vec2(quad_shader_program, "screen_res", {f32(wx^), f32(wy^)})
}

handle_input :: proc(event: sdl.Event) -> bool {
	etype := event.type
	if etype == .QUIT {
		return false
	}
	if etype == .MOUSEMOTION {
		sdl.GetMouseState(&ui_state.mouse.pos.x, &ui_state.mouse.pos.y)
	}
	if etype == .KEYDOWN {
		#partial switch event.key.keysym.sym {
		case .ESCAPE:
			return false
		case .SPACE:
			audio_state.playing = !audio_state.playing
		}
	}
	if etype == .MOUSEWHEEL {
		ui_state.mouse.wheel.x = cast(i8)event.wheel.x
		ui_state.mouse.wheel.y = cast(i8)event.wheel.y
	}
	if etype == .MOUSEBUTTONDOWN {
		switch event.button.button {
		case sdl.BUTTON_LEFT:
			if !ui_state.mouse.left_pressed {
				ui_state.mouse.drag_start = ui_state.mouse.pos
				ui_state.mouse.dragging = true
			}
			ui_state.mouse.left_pressed = true
		case sdl.BUTTON_RIGHT:
			ui_state.mouse.right_pressed = true
		}
	}
	if etype == .MOUSEBUTTONUP {
		println("mouse up ")
		switch event.button.button {
		case sdl.BUTTON_LEFT:
			ui_state.mouse.left_pressed = false
			ui_state.mouse.drag_end = ui_state.mouse.pos
			ui_state.mouse.dragging = false
		case sdl.BUTTON_RIGHT:
			ui_state.mouse.right_pressed = false
		}
	}
	if etype == .DROPFILE {
		which, on_track := dropped_on_track()
		assert(on_track)
		if on_track {
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
