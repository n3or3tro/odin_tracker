// Basic abstraction to make working with OpenGL shaders easier.

package main
import "core:fmt"
import alg "core:math/linalg"
import "core:os"
import "core:strings"
import gl "vendor:OpenGL"

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

shader_as_cstring :: proc(path: string) -> string {
	data, ok := os.read_entire_file_from_filename(path)
	if !ok {
		panic("Failed to read file: ")
	}
	return strings.clone_from_bytes(data)
}

create_shader :: proc(vshader_path: string, fshader_path: string) -> u32 {
	// simpler way
	// pid , ok := gl.load_shaders_source(vertex_shader, fragment_shader)
	// if !ok {
	// 	fmt.eprintln("Failed to create GLSL program")
	// 	panic("Failed to create GLSL program")
	// } 	
	vertex_shader := shader_as_cstring(vshader_path)
	fragment_shader := shader_as_cstring(fshader_path)
	shader_program := gl.CreateProgram()
	vs, verr := gl.compile_shader_from_source(vertex_shader, .VERTEX_SHADER)
	fs, ferr := gl.compile_shader_from_source(fragment_shader, .FRAGMENT_SHADER)
	if !verr || !ferr {
		panic(
			"Failed to compile vertex or fragment shader. Probably break up this check to give more information.",
		)
	}
	// this makes it impossible to debug, pretty sure it deletes the shader code from the gpu, but the 
	// ?binary? is still there. (not really sure)
	defer gl.DeleteShader(vs)
	defer gl.DeleteShader(fs)

	gl.AttachShader(shader_program, vs)
	gl.AttachShader(shader_program, fs)
	gl.LinkProgram(shader_program)
	gl.ValidateProgram(shader_program)

	result: i32
	gl.GetShaderiv(shader_program, gl.LINK_STATUS, &result)
	if result != 0 {
		fmt.println("!!!!\n!!!!\nbig fucken errors\n!!!!\n!!!!")
		length: i32
		gl.GetProgramiv(shader_program, gl.INFO_LOG_LENGTH, &length)
		// log := make([]u8, length)
		log: [200]u8
		gl.GetProgramInfoLog(shader_program, 200, &length, &log[0])
		fmt.println("Failed to link shader program: ", log)
		panic("fuck")
		// return 0
	}
	// gl.ValidateProgram(shader_program)
	return shader_program
}

bind_shader :: proc(shader_program: u32) {
	gl.UseProgram(shader_program)
}

create_and_bind_shader :: proc(vshader_path: string, fshader_path: string) -> u32 {
	program := create_shader(vshader_path, fshader_path)
	bind_shader(program)
	return program
}

set_shader_bool :: proc(shader: u32, name: cstring, value: bool) {
	val: i32 = 1 if value else 0
	gl.Uniform1i(gl.GetUniformLocation(shader, name), val)
}

set_shader_u32 :: proc(shader: u32, name: cstring, value: u32) {
	gl.Uniform1ui(gl.GetUniformLocation(shader, name), value)
}

set_shader_i32 :: proc(shader: u32, name: cstring, value: i32) {
	gl.Uniform1i(gl.GetUniformLocation(shader, name), value)
}

set_shader_f32 :: proc(shader: u32, name: cstring, value: f32) {
	gl.Uniform1f(gl.GetUniformLocation(shader, name), value)
}
set_shader_matrix2 :: proc(shader: u32, name: cstring, value: ^alg.Matrix2x2f32) {
	gl.UniformMatrix2fv(gl.GetUniformLocation(shader, name), 1, gl.FALSE, raw_data(value))
}
set_shader_matrix3 :: proc(shader: u32, name: cstring, value: ^alg.Matrix3x3f32) {
	gl.UniformMatrix3fv(gl.GetUniformLocation(shader, name), 1, gl.FALSE, raw_data(value))

}
set_shader_matrix4 :: proc(shader: u32, name: cstring, value: ^alg.Matrix4x4f32) {
	gl.UniformMatrix4fv(gl.GetUniformLocation(shader, name), 1, gl.FALSE, raw_data(value))

}
set_shader_vec3 :: proc(shader: u32, name: cstring, value: Vec3) {
	gl.Uniform3f(gl.GetUniformLocation(shader, name), value.x, value.y, value.z)
}
set_shader_vec2 :: proc(shader: u32, name: cstring, value: Vec2) {
	gl.Uniform2f(gl.GetUniformLocation(shader, name), value.x, value.y)
}

delete_shader :: proc(shader_program: u32) {
	gl.DeleteProgram(shader_program)
}
