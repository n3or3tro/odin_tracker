#version 460 core
// layout(location = 0) out vec4 color;
// uniform vec4 in_color;

in vec4 vertex_colors;
out vec4 color;
void main() {
	// color = in_color;
    color = vertex_colors;
}
