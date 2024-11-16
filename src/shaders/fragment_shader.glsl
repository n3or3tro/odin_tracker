#version 460 core

in vec4 vertex_colors;

out vec4 color;

void main() {
	color = vertex_colors;
}
