package main
import "base:intrinsics"
import "core:fmt"
import "core:io"
import "core:math"
import alg "core:math/linalg"
import glm "core:math/linalg/glsl"
import "core:strings"
import "core:thread"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"
import sttf "vendor:sdl2/ttf"
println :: fmt.println
WINDOW_WIDTH :: 3000
WINDOW_HEIGHT :: 2000


main :: proc() {
	wx: i32 = WINDOW_WIDTH
	wy: i32 = WINDOW_HEIGHT
	window, gl_context := setup_window()

	vertices: []f32 = {-1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0, 1.0}

	vbo: u32
	gl.GenBuffers(1, &vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), rawptr(&vertices), gl.STATIC_DRAW)
	
	// odinfmt: disable
	instance_data:[]f32 = {
		// p0.x, p0.y, p1.x, p1.y, 	r, 	g, 	  b, 	a
		100.0, 100.0, 200.0, 200.0, 1.0, 0.0, 0.0, 1.0, // Instance 1
		300.0, 300.0, 400.0, 400.0, 0.0, 1.0, 0.0, 1.0, // Instance 2
	}
	// odinfmt: enable

	instance_vbo: u32
	gl.GenBuffers(1, &instance_vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, instance_vbo)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(instance_data), rawptr(&instance_data), gl.STATIC_DRAW)

	// Enable instance attributes
	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, 8 * size_of(f32), uintptr(0)) // p0
	gl.EnableVertexAttribArray(0)
	gl.VertexAttribDivisor(0, 1)


	gl.VertexAttribPointer(1, 2, gl.FLOAT, false, 8 * size_of(f32), uintptr(0)) // p1
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribDivisor(1, 1)

	gl.VertexAttribPointer(2, 4, gl.FLOAT, false, 8 * size_of(f32), 2 * size_of(f32)) // p1
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribDivisor(1, 1)

	gl.VertexAttribPointer(2, 4, gl.FLOAT, false, 8 * size_of(f32), 4 * size_of(f32)) // color
	gl.EnableVertexAttribArray(2)

	shader_program := create_and_bind_shader("src/vertex.glsl", "src/pixel.glsl")

	set_shader_vec2(shader_program, "res", {3000, 2000})
	app_loop: for {
		sdl.GetWindowSize(window, &wx, &wy)
		event: sdl.Event
		for sdl.PollEvent(&event) {
			if !handle_input(event) {
				println("quit event received, exiting...")
				break app_loop
			}
		}

		clear()
		gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, 2)
		sdl.GL_SwapWindow(window)
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
		if event.button.button == sdl.BUTTON_LEFT {
			println("clicked")
		}
		if event.button.button == sdl.BUTTON_RIGHT {
			println("clicked")
		}
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

clear :: proc() {
	gl.ClearColor(1, 0.5, 1, 1.0)
	gl.Clear(gl.COLOR_BUFFER_BIT)
}
