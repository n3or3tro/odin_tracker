package main
import "base:runtime"
import "core:dynlib"
import "core:flags"
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
import gl "vendor:OpenGL"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"
import "vendor:stb/image"

println :: fmt.println
printf :: fmt.printf
printfln :: fmt.printfln
aprintf :: fmt.aprintf
tprintf :: fmt.tprintf
tprintfln :: fmt.aprintfln

PROFILING :: #config(profile, false)

when ODIN_OS == .Windows {
	WINDOW_WIDTH := 1500
	WINDOW_HEIGHT := 1000
} else {
	WINDOW_WIDTH := 2500
	WINDOW_HEIGHT := 1500
}
ASPECT_RATIO: f32 : 16.0 / 10.0


// [NOTE]: Pretty sure that anything that's a pointer inside this struct needs to malloc'd.
App_State :: struct {
	window:          ^sdl.Window,
	ui_state:        ^UI_State,
	char_map:        ^u32,
	mouse:           struct {
		pos:           [2]i32, // these are typed like this to follow the SDL api, else, they'd be u16
		last_pos:      [2]i32, // pos of the mouse in the last frame.
		drag_start:    [2]i32, // -1 if drag was already handled
		drag_end:      [2]i32, // -1 if drag was already handled
		dragging:      bool,
		drag_done:     bool,
		left_pressed:  bool,
		right_pressed: bool,
		wheel:         [2]i8, //-1 moved down, +1 move up
		clicked:       bool, // whether mouse was left clicked in this frame.
		right_clicked: bool, // whether mouse was right clicked in this frame.
	},
	// Actual pixel values of the window.
	wx:              ^i32,
	wy:              ^i32,
	audio_state:     ^Audio_State,
	hot_id:          string,
	active_id:       string,
	sampler_open:    bool,
	// top left of the sampler window
	sampler_pos:     Vec2,
	dragging_window: bool,
	n_tracks:        u8,
	acitve_tab:      u8,
}

N_TRACKS :: 10

app: ^App_State
ui_state: ^UI_State

ui_vertex_shader_data :: #load("shaders/box_vertex_shader.glsl")
ui_pixel_shader_data :: #load("shaders/box_pixel_shader.glsl")

when PROFILING {
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
}

main :: proc() {
	when PROFILING {
		spall_ctx = spall.context_create("trace_test.spall")
		defer spall.context_destroy(&spall_ctx)

		backing_buffer := make([]u8, spall.BUFFER_DEFAULT_SIZE)
		defer delete(backing_buffer)

		spall_buffer = spall.buffer_create(backing_buffer, u32(sync.current_thread_id()))
		defer spall.buffer_destroy(&spall_ctx, &spall_buffer)

		spall.SCOPED_EVENT(&spall_ctx, &spall_buffer, #procedure)
	}
	init_app()
	for {
		desired_frame_time: int = 1000 / 120
		start := time.now()._nsec
		if !update_app() {
			break
		}
		frame_time := f32(start - time.now()._nsec) / 1_000
	}
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
	gl.Disable(gl.BLEND)
	// gl.Enable(gl.Depth)
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

	ui_state.rect_stack = make([dynamic]^Rect)
	ui_state.color_stack = make([dynamic]Color)
	append(&ui_state.rect_stack, ui_state.root_rect)
	ui_state.box_cache = make(map[string]^Box)
	ui_state.temp_boxes = make([dynamic]^Box)
	ui_state.first_frame = true

	gl.GenVertexArrays(1, ui_state.quad_vabuffer)
	create_vbuffer(ui_state.quad_vbuffer, nil, 400_000)

	program1, quad_shader_ok := gl.load_shaders_source(
		string(ui_vertex_shader_data),
		string(ui_pixel_shader_data),
	)
	assert(quad_shader_ok)
	ui_state.quad_shader_program = program1


	bind_shader(ui_state.quad_shader_program)
	set_shader_vec2(
		ui_state.quad_shader_program,
		"screen_res",
		{f32(WINDOW_WIDTH), f32(WINDOW_HEIGHT)},
	)

	ui_state.atlas_metadata = parse_font_metadata("font-atlas/Unnamed.fnt")

	set_shader_i32(
		ui_state.quad_shader_program,
		"font_texture_height",
		i32(ui_state.atlas_metadata.texture.texture_height),
	)
	set_shader_i32(
		ui_state.quad_shader_program,
		"font_texture_width",
		i32(ui_state.atlas_metadata.texture.texture_width),
	)

	font_texture_data := #load("../font-atlas/Unnamed.png")
	texture_x, texture_y, texture_channels: i32
	image.set_flip_vertically_on_load(1)
	texture_data := image.load_from_memory(
		raw_data(font_texture_data),
		i32(len(font_texture_data)),
		&texture_x,
		&texture_y,
		&texture_channels,
		4,
	)
	defer image.image_free(texture_data)

	texutre_id := new(u32)
	gl.ActiveTexture(gl.TEXTURE0)
	gl.GenTextures(1, texutre_id)
	gl.BindTexture(gl.TEXTURE_2D, texutre_id^)

	// Set texture parameters (wrap/filter) for font
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

	// Upload to GPU
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.RGBA,
		i32(ui_state.atlas_metadata.texture.texture_width),
		i32(ui_state.atlas_metadata.texture.texture_height),
		0,
		gl.RGBA,
		gl.UNSIGNED_BYTE,
		texture_data,
	)
	set_shader_i32(program1, "font_texture", 0)

	/*
	---------------- Circle knob texture stuff -----------------------------------------------------
	*/
	// load knob texture image 
	knob_width, knob_height, channels: i32
	raw_image_data := #load("../textures/knob.png")
	knob_image_data := image.load_from_memory(
		raw_data(raw_image_data),
		i32(len(raw_image_data)),
		&knob_width,
		&knob_height,
		&channels,
		4,
	)
	printfln("image data: {}x{}  - {}", knob_width, knob_height, channels)

	knob_texture_id := new(u32)
	gl.ActiveTexture(gl.TEXTURE1)
	gl.GenTextures(1, knob_texture_id)
	gl.BindTexture(gl.TEXTURE_2D, knob_texture_id^)

	// Upload texture data to OpenGL
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.RGBA,
		knob_width,
		knob_height,
		0,
		gl.RGBA,
		gl.UNSIGNED_BYTE,
		knob_image_data,
	)
	// glGenerateMipmap(GL_TEXTURE_2D)

	// // Set texture parameters
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.Uniform1i(gl.GetUniformLocation(program1, "circle_knob_texture"), 1)

	// stbi_image_free(data)

	/*
	---------------- Fader knob texture stuff -----------------------------------------------------
	*/
	fader_knob_width, fader_knob_height: i32
	channels = 0
	fader_knob_raw_image_data := #load("../textures/fader-knob.png")
	fader_knob_image_data := image.load_from_memory(
		raw_data(fader_knob_raw_image_data),
		i32(len(fader_knob_raw_image_data)),
		&fader_knob_width,
		&fader_knob_height,
		&channels,
		4,
	)

	fader_knob_texture_id := new(u32)
	gl.ActiveTexture(gl.TEXTURE2)
	gl.GenTextures(1, fader_knob_texture_id)
	gl.BindTexture(gl.TEXTURE_2D, fader_knob_texture_id^)

	// Upload texture data to OpenGL
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.RGBA,
		fader_knob_width,
		fader_knob_height,
		0,
		gl.RGBA,
		gl.UNSIGNED_BYTE,
		fader_knob_image_data,
	)
	// glGenerateMipmap(GL_TEXTURE_2D)

	// // Set texture parameters
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.Uniform1i(gl.GetUniformLocation(program1, "fader_knob_texture"), 2)

	/*
	---------------- Background texture stuff -----------------------------------------------------
	*/
	background_img_width, background_img_height: i32
	channels = 0
	background_img_raw_image_data := #load("../textures/metal-background.jpeg")
	background_image_data := image.load_from_memory(
		raw_data(background_img_raw_image_data),
		i32(len(background_img_raw_image_data)),
		&background_img_width,
		&background_img_height,
		&channels,
		4,
	)

	background_texture_id := new(u32)
	gl.ActiveTexture(gl.TEXTURE3)
	gl.GenTextures(1, background_texture_id)
	gl.BindTexture(gl.TEXTURE_2D, background_texture_id^)

	// Upload texture data to OpenGL
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.RGBA,
		background_img_width,
		background_img_height,
		0,
		gl.RGBA,
		gl.UNSIGNED_BYTE,
		background_image_data,
	)
	// glGenerateMipmap(GL_TEXTURE_2D)

	// // Set texture parameters
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.Uniform1i(gl.GetUniformLocation(program1, "background_texture"), 3)


	setup_for_quads(&ui_state.quad_shader_program)
	sdl.GetWindowSize(app.window, app.wx, app.wy)
	ui_state.frame_num = new(u64)
	ui_state.frame_num^ = 0

	return ui_state
}

init_app :: proc() -> ^App_State {
	app = new(App_State)
	app.sampler_pos = {100, 100}
	init_window()
	app.ui_state = new(UI_State)
	ui_state = app.ui_state
	init_ui_state()
	setup_audio()
	app.n_tracks += 1
	return app
}


update_app :: proc() -> bool {
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

	if app.audio_state.playing {
		if frame_num^ % (30) == 0 {
			for &track in app.audio_state.tracks {
				if track.armed {
					track.curr_step = (track.curr_step + 1) % 32
				}
			}
		}
	}

	create_ui()
	render_ui()
	reset_renderer_data()
	sdl.GL_SwapWindow(app.window)

	free_all(context.temp_allocator)
	free_all()
	frame_num^ += 1
	return true
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
		app.mouse.last_pos = app.mouse.pos
		sdl.GetMouseState(&app.mouse.pos.x, &app.mouse.pos.y)
	}
	if etype == .KEYDOWN {
		#partial switch event.key.keysym.sym {
		case .ESCAPE:
			return false
		case .SPACE: app.audio_state.playing = !app.audio_state.playing
		}
	}
	if etype == .MOUSEWHEEL {
		app.mouse.wheel.x = cast(i8)event.wheel.x
		app.mouse.wheel.y = cast(i8)event.wheel.y
	}
	if etype == .MOUSEBUTTONDOWN {
		switch event.button.button {
		case sdl.BUTTON_LEFT:
			if !app.mouse.left_pressed { 	// i.e. if left button wasn't pressed last frame
				app.mouse.drag_start = app.mouse.pos
				app.mouse.dragging = true
				app.mouse.drag_done = false
			}
			app.mouse.left_pressed = true
		// ui_state.context_menu_active = false
		case sdl.BUTTON_RIGHT:
			app.mouse.right_pressed = true
			if ui_state.context_menu_active {

			} else {
				ui_state.context_menu_pos = Vec2{f32(app.mouse.pos.x), f32(app.mouse.pos.y)}
				ui_state.context_menu_active = true
			}
		}
	}
	if etype == .MOUSEBUTTONUP {
		switch event.button.button {
		case sdl.BUTTON_LEFT:
			if app.mouse.left_pressed {
				app.mouse.clicked = true
			}
			app.mouse.left_pressed = false
			app.mouse.drag_end = app.mouse.pos
			app.mouse.dragging = false
			app.mouse.drag_done = true
			app.dragging_window = false
			printf("mouse was dragged from {} to {}\n", app.mouse.drag_start, app.mouse.drag_end)
		case sdl.BUTTON_RIGHT:
			if app.mouse.right_pressed {
				app.mouse.right_clicked = true
			}
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
	app.mouse.last_pos = app.mouse.pos
	if app.mouse.clicked {
		println("mouse clicked")
		// do this here because events are captured before ui is created, 
		// meaning context-menu.button1.signals.click will never be set.
		ui_state.context_menu_active = false
	}
	app.mouse.clicked = false
	app.mouse.right_clicked = false
}
