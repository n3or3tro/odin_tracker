#version 410 core

// // need to be careful how these 'extensions' affect cross-platform
// // compatibility. This feature requires OpenGL 4.3
// #extension GL_ARB_explicit_uniform_location : require

layout(location = 0) in vec2 p0;      // Top-left corner of rectangle (per-instance)
layout(location = 1) in vec2 p1;      // Bottom-right corner of rectangle (per-instance)

layout(location = 2) in vec4 tl_color;
layout(location = 3) in vec4 tr_color;
layout(location = 4) in vec4 bl_color;
layout(location = 5) in vec4 br_color;

layout(location = 6) in float corner_radius;
layout(location = 7) in float edge_softness;  // Used for shadows and shit I think. 
layout(location = 8) in float border_thickness;  // Used for shadows and shit I think. 

// layout(location = 9) in float tl_texture;
// layout(location = 10) in float br_texture;

layout(location = 0) out vec4 v_color;
layout(location = 1) out vec2 out_dst_pos;
layout(location = 2) out vec2 out_dst_center;
layout(location = 3) out vec2 out_dst_half_size;
layout(location = 4) out float out_corner_radius;
layout(location = 5) out float out_edge_softness;
layout(location = 6) out float out_border_thickness;

// layout(location = 7) out vec2 texture_uv;

uniform vec2 screen_res = vec2(3000, 2000);

void main() {
	vec4[4] colors;
	colors[0] = tl_color;
	colors[1] = tr_color;
	colors[2] = bl_color;
	colors[3] = br_color;

    // Static vertex array mapped to gl_VertexID
	vec2 vertices[4] = vec2[](vec2(-1.0, -1.0), vec2(-1.0, 1.0), vec2(1.0, -1.0), vec2(1.0, 1.0));

	vec2 dst_half_size = (p1 - p0) / 2.0;
	vec2 dst_center = (p1 + p0) / 2.0;
	vec2 dst_pos = (vertices[gl_VertexID] * dst_half_size) + dst_center;

	// Texture stuff :)
	// vec2 tex_half_size = (p1 - p0) / 2;
	// vec2 tex_center = (p1 + p0) / 2;
	// vec2 tex_pos = (vertices[gl_VertexID] * tex_half_size + tex_center)
	// texture_uv = vec2(tex_pos.x/)

    // Map to screen coordinates (-1 to 1 NDC)
	// vec2 ndc_pos = 2.0 * dst_pos / screen_res - vec2(1.0);

    // Output data for pixel shader
	v_color = colors[gl_VertexID];
	out_dst_pos = dst_pos;
	out_dst_center = dst_center;
	out_dst_half_size = dst_half_size;
	out_corner_radius = corner_radius;
	out_edge_softness = edge_softness;
	out_border_thickness = border_thickness;

	gl_Position = vec4(2 * dst_pos.x / screen_res.x - 1, -1 * (2 * dst_pos.y / screen_res.y - 1), 0.0, 1.0);
}
