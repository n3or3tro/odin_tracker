#version 410 core

layout(location = 0) in vec2 p0;      // Top-left corner of rectangle (per-instance)
layout(location = 1) in vec2 p1;      // Bottom-right corner of rectangle (per-instance)
layout(location = 2) in vec4 color;   // Rectangle color (per-instance)

out vec4 v_color;

void main() {
    // Static vertex array mapped to gl_VertexID
	vec2 vertices[4] = vec2[](vec2(-1.0, -1.0), vec2(-1.0, 1.0), vec2(1.0, -1.0), vec2(1.0, 1.0));

    // Calculate destination propvec2 res = vec2(2000, 1500);erties
	vec2 dst_half_size = (p1 - p0) / 2.0;
	vec2 dst_center = (p1 + p0) / 2.0;
	vec2 dst_pos = (vertices[gl_VertexID] * dst_half_size) + dst_center;
	vec2 res = vec2(2000, 1500); // Resolution of the screen
    // Map to screen coordinates (-1 to 1 NDC)
	vec2 ndc_pos = 2.0 * dst_pos / res - vec2(1.0);

    // Output position and pass color
	gl_Position = vec4(ndc_pos.xy, 0.0, 1.0);
	v_color = color;
}
