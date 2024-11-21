#version 460 core

in vec4 vColor; // Interpolated color from vertex shader

out vec4 fragColor; // Output color

void main() {
    fragColor = vColor; // Use the per-rectangle color
}