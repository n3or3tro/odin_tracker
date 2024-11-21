#version 410 core

in vec4 v_color;

out vec4 fragColor;

void main() {
	fragColor = v_color; // Use the per-rectangle color
}