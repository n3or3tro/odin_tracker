#version 460 core
layout(location = 0) in vec2 positions;
layout(location = 1) in vec4 color;
uniform mat2 rot_matrix;
out vec4 vertex_colors;
void main() {
    vec2 tmp = rot_matrix * positions;
    gl_Position = vec4(tmp.x, tmp.y, 0.0, 1.0);
    vertex_colors = color;
}