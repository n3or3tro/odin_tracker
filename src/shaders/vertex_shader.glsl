#version 460 core
layout(location = 0) in vec2 positions;
layout(location = 1) in vec4 color;

uniform mat4 proj;

out vec4 vertex_colors;
void main() {
	gl_Position = proj * vec4(positions.x, positions.y, 0.0, 1.0);
	vertex_colors = color;
}