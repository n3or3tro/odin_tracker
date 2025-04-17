package main
import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:io"
import "core:math"
import alg "core:math/linalg"
import "core:mem"
import "core:os"
import "core:prof/spall"
import s "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import tracy "third_party/odin-tracy"
import gl "vendor:OpenGL"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"
import sttf "vendor:sdl2/ttf"

println :: fmt.println
printf :: fmt.printf
aprintf :: fmt.aprintf
tprintf :: fmt.tprintf
tprintfln :: fmt.aprintfln


WINDOW_WIDTH := 3000
WINDOW_HEIGHT := 2000
ASPECT_RATIO: f32 : 16.0 / 10.0


// [NOTE]: Pretty sure that anything that's a pointer inside this struct needs to malloc'd.
App_State :: struct {
	window:      ^sdl.Window,
	ui_state:    ^UI_State,
	ui_font:     ^sttf.Font,
	char_map:    ^u32,
	mouse:       struct {
		pos:           [2]i32, // these are typed like this to follow the SDL api, else, they'd be u16
		drag_start:    [2]i32, // -1 if drag was already handled
		drag_end:      [2]i32, // -1 if drag was already handled
		dragging:      bool,
		left_pressed:  bool,
		right_pressed: bool,
		wheel:         [2]i8, //-1 moved down, +1 move up
	},
	// Actual pixel values of the window.
	wx:          ^i32,
	wy:          ^i32,
	audio_state: ^Audio_State,
	hot_id:      string,
	active_id:   string,
}
N_TRACKS :: 10

app: ^App_State
ui_state: ^UI_State

ui_vertex_shader_data :: #load("shaders/box_vertex_shader.glsl")
ui_pixel_shader_data :: #load("shaders/box_pixel_shader.glsl")

text_vertex_shader_data :: #load("shaders/text_vertex_shader.glsl")
text_pixel_shader_data :: #load("shaders/text_pixel_shader.glsl")

wave_vertex_shader_data :: #load("shaders/wave_vertex_shader.glsl")
wave_pixel_shader_data :: #load("shaders/wave_pixel_shader.glsl")

spall_ctx: spall.Context

@(thread_local)
spall_buffer: spall.Buffer

//------------------ Automatic profiling of every procedure:-----------------
@(instrumentation_enter)
spall_enter :: proc "contextless" (
	proc_address, call_site_return_address: rawptr,
	loc: runtime.Source_Code_Location,
) {
	spall._buffer_begin(&spall_ctx, &spall_buffer, "", "", loc)
}

@(instrumentation_exit)
spall_exit :: proc "contextless" (
	proc_address, call_site_return_address: rawptr,
	loc: runtime.Source_Code_Location,
) {
	spall._buffer_end(&spall_ctx, &spall_buffer)
}
// -----------------------------------------------------------------------

main :: proc() {
	// spall_ctx = spall.context_create("trace_test.spall")
	// defer spall.context_destroy(&spall_ctx)

	// backing_buffer := make([]u8, spall.BUFFER_DEFAULT_SIZE)
	// defer delete(backing_buffer)

	// spall_buffer = spall.buffer_create(backing_buffer, u32(sync.current_thread_id()))
	// defer spall.buffer_destroy(&spall_ctx, &spall_buffer)

	// spall.SCOPED_EVENT(&spall_ctx, &spall_buffer, #procedure)
	app_init()
	for {
		if !app_update() {
			break
		}
	}
	// app_shutdown()
}

init_window :: proc() -> (^sdl.Window, sdl.GLContext) {
	// sdl.Init({.AUDIO, .EVENTS, .TIMER})
	sdl.Init({.EVENTS})

	window_flags :=
		sdl.WINDOW_OPENGL | sdl.WINDOW_RESIZABLE | sdl.WINDOW_ALLOW_HIGHDPI | sdl.WINDOW_UTILITY
	app.window = sdl.CreateWindow(
		"n3or3tro-tracker",
		sdl.WINDOWPOS_UNDEFINED,
		sdl.WINDOWPOS_UNDEFINED,
		i32(WINDOW_WIDTH),
		i32(WINDOW_HEIGHT),
		window_flags,
	)
	if app.window == nil {
		panic("Failed to create window")
	}

	// Set OpenGL attributes after SDL initialization
	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
	sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 1)
	sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, gl.CONTEXT_CORE_PROFILE_BIT)
	sdl.GL_SetAttribute(.MULTISAMPLEBUFFERS, 1)
	sdl.GL_SetAttribute(.MULTISAMPLESAMPLES, 8)

	gl_context := sdl.GL_CreateContext(app.window)
	if gl_context == nil {
		panic("Failed to create OpenGL context")
	}
	sdl.GL_MakeCurrent(app.window, gl_context)

	gl.load_up_to(4, 1, sdl.gl_set_proc_address)

	// Enable OpenGL settings
	gl.Hint(gl.LINE_SMOOTH_HINT, gl.NICEST)
	gl.Hint(gl.POLYGON_SMOOTH_HINT, gl.NICEST)
	gl.Enable(gl.LINE_SMOOTH)
	gl.Enable(gl.POLYGON_SMOOTH)
	gl.Enable(gl.MULTISAMPLE)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	return app.window, gl_context
}

init_ui_state :: proc() -> ^UI_State {
	ui_state.root_rect = new(Rect)

	app.wx = new(i32)
	app.wy = new(i32)

	ui_state.quad_vbuffer = new(u32)
	ui_state.quad_vabuffer = new(u32)

	ui_state.text_vbuffer = new(u32)
	ui_state.text_vabuffer = new(u32)

	ui_state.rect_stack = make([dynamic]^Rect)
	ui_state.color_stack = make([dynamic]Color)
	append(&ui_state.rect_stack, ui_state.root_rect)
	ui_state.box_cache = make(map[string]^Box)
	ui_state.temp_boxes = make([dynamic]^Box)
	ui_state.first_frame = true

	gl.GenVertexArrays(1, ui_state.quad_vabuffer)
	gl.GenVertexArrays(1, ui_state.text_vabuffer)
	create_vbuffer(ui_state.quad_vbuffer, nil, 500_000)
	program1, quad_shader_ok := gl.load_shaders_source(
		string(ui_vertex_shader_data),
		string(ui_pixel_shader_data),
	)
	assert(quad_shader_ok)
	ui_state.quad_shader_program = program1

	program2, text_shader_ok := gl.load_shaders_source(
		string(text_vertex_shader_data),
		string(text_pixel_shader_data),
	)
	assert(text_shader_ok)
	ui_state.text_shader_program = program2

	bind_shader(ui_state.quad_shader_program)
	set_shader_vec2(
		ui_state.quad_shader_program,
		"screen_res",
		{f32(WINDOW_WIDTH), f32(WINDOW_HEIGHT)},
	)

	ui_state.char_map = create_font_map(30)
	create_vbuffer(ui_state.text_vbuffer, nil, 100_000 * size_of(f32))

	setup_for_quads(&ui_state.quad_shader_program)
	sdl.GetWindowSize(app.window, app.wx, app.wy)
	ui_state.frame_num = new(u64)
	ui_state.frame_num^ = 0
	return ui_state
}

@(export)
app_init :: proc() -> ^App_State {
	app = new(App_State)
	init_window()
	app.ui_state = new(UI_State)
	ui_state = app.ui_state
	init_ui_state()
	setup_audio()
	return app
}

@(export)
app_update :: proc() -> bool {
	defer tracy.FrameMark()
	{
		tracy.Zone()
	}
	root_rect := app.ui_state.root_rect
	frame_num := app.ui_state.frame_num
	if register_resize() {
		set_shader_vec2(ui_state.quad_shader_program, "screen_res", {f32(app.wx^), f32(app.wy^)})
	}
	ui_state.root_rect.top_left = {0, 0}
	ui_state.root_rect.bottom_right = {f32(app.wx^), f32(app.wy^)}
	event: sdl.Event
	reset_mouse_state()
	for sdl.PollEvent(&event) {
		if !handle_input(event) {
			return false
		}
	}
	clear_screen()
	create_ui()
	render_ui()
	render_text2()
	reset_renderer_data()
	sdl.GL_SwapWindow(app.window)
	if app.audio_state.playing {
		// at 120 fps, a 1/4 beat lasts for 30 frames. This is probably too hard coded
		// and fragile, should be made more robust...
		if frame_num^ % (30) == 0 {
			app.audio_state.curr_step = (app.audio_state.curr_step + 1) % u16(n_track_steps) // 32 == n_steps per track.
			play_current_step()
		}
	}
	free_all(context.temp_allocator)
	free_all()
	frame_num^ += 1
	return true
}

@(export)
app_shutdown :: proc() {

}

@(export)
app_memory :: proc() -> rawptr {
	return app
}


// stupid_sem: sync.Atomic_Sema
run_app :: proc() {
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

handle_input :: proc(event: sdl.Event) -> bool {
	etype := event.type
	if etype == .QUIT {
		return false
	}
	if etype == .MOUSEMOTION {
		sdl.GetMouseState(&app.mouse.pos.x, &app.mouse.pos.y)
	}
	if etype == .KEYDOWN {
		#partial switch event.key.keysym.sym {
		case .ESCAPE:
			return false
		case .SPACE:
			app.audio_state.playing = !app.audio_state.playing
		}
	}
	if etype == .MOUSEWHEEL {
		app.mouse.wheel.x = cast(i8)event.wheel.x
		app.mouse.wheel.y = cast(i8)event.wheel.y
	}
	if etype == .MOUSEBUTTONDOWN {
		switch event.button.button {
		case sdl.BUTTON_LEFT:
			if !app.mouse.left_pressed {
				app.mouse.drag_start = app.mouse.pos
				app.mouse.dragging = true
			}
			app.mouse.left_pressed = true
		case sdl.BUTTON_RIGHT:
			app.mouse.right_pressed = true
		}
	}
	if etype == .MOUSEBUTTONUP {
		println("mouse up ")
		switch event.button.button {
		case sdl.BUTTON_LEFT:
			app.mouse.left_pressed = false
			app.mouse.drag_end = app.mouse.pos
			app.mouse.dragging = false
		case sdl.BUTTON_RIGHT:
			app.mouse.right_pressed = false
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
	old_width, old_height := app.wx^, app.wy^
	sdl.GetWindowSize(app.window, app.wx, app.wy)
	if old_width != app.wx^ || old_height != app.wy^ {
		gl.Viewport(0, 0, app.wx^, app.wy^)
		return true
	}
	return false
}

resize_window :: proc() {
	// sdl.SetWindowSize(window, wx^, wy^)
	set_shader_vec2(ui_state.quad_shader_program, "screen_res", {f32(app.wx^), f32(app.wy^)})
}

reset_mouse_state :: proc() {
	app.mouse.wheel = {0, 0}
}
