#version 410 core

layout(location = 0) in vec4 v_color;

// At the moment, a fragment == a pixel.
out vec4 fragColor;

void main() {
	fragColor = v_color; // Use the per-rectangle color
}